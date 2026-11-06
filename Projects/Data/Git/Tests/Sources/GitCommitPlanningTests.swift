import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitCommitPlanningTests {
	private final class Context: Sendable {
		let url: URL
		let runner: GitProcessRunner
		let repository: LocalGitRepository

		init(url: URL, runner: GitProcessRunner) {
			self.url = url
			self.runner = runner
			repository = LocalGitRepository(runner: runner)
		}

		deinit { try? FileManager.default.removeItem(at: url) }
	}

	@Test
	func separateTasksInOneFilePreserveStagingAndUnstagedEdits() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		let original = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"
		try original.write(to: file, atomically: true, encoding: .utf8)
		try await run(["add", "file.txt"], in: context)
		try await run(["commit", "-m", "initial"], in: context)
		let staged = original.replacingOccurrences(of: "line 2\n", with: "first task\nextra line\n")
			.replacingOccurrences(of: "line 10\n", with: "second task\n")
		try staged.write(to: file, atomically: true, encoding: .utf8)
		try await run(["add", "file.txt"], in: context)
		let working = staged + "unstaged work\n"
		try working.write(to: file, atomically: true, encoding: .utf8)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		#expect(input.units.count == 2)
		let first = try #require(input.units.first)
		let second = try #require(input.units.last)
		let analysis = GitCommitUnitParser.analysisPatch(for: first)
		#expect(analysis.contains("+first task"))
		#expect(!analysis.contains("diff --git"))
		#expect(!analysis.contains("index "))
		let index = try Data(contentsOf: context.url.appending(path: ".git/index"))
		try await context.repository.requestCommitTask(
			GitCommitTask(subject: "feat: first task", body: "", unitIDs: [first.id]),
			expecting: input, at: context.url)

		#expect(try Data(contentsOf: context.url.appending(path: ".git/index")) == index)
		#expect(try String(contentsOf: file, encoding: .utf8) == working)
		let committed = try await output(["show", "HEAD:file.txt"], in: context)
		#expect(committed.contains("first task"))
		#expect(!committed.contains("second task"))
		let remaining = try await context.repository.requestCommitPlanInput(at: context.url)
		#expect(remaining.units.map(\.id) == [second.id])
		try await context.repository.requestCommitTask(
			GitCommitTask(subject: "feat: second task", body: "", unitIDs: [second.id]),
			expecting: remaining, at: context.url)
		#expect(try await output(["show", "HEAD:file.txt"], in: context) == staged)
		#expect(try await output(["diff", "--cached"], in: context).isEmpty)
		#expect(try String(contentsOf: file, encoding: .utf8) == working)
	}

	@Test
	func selectedHunksCombineWithoutCommittingAnotherFile() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		let base = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"
		try base.write(to: file, atomically: true, encoding: .utf8)
		try await run(["add", "."], in: context)
		try await run(["commit", "-m", "initial"], in: context)
		try base.replacingOccurrences(of: "line 2", with: "updated 2")
			.replacingOccurrences(of: "line 10", with: "updated 10")
			.write(to: file, atomically: true, encoding: .utf8)
		try Data("unrelated\n".utf8).write(to: context.url.appending(path: "other.txt"))
		try await run(["add", "."], in: context)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		let ids = input.units.filter { $0.path == "file.txt" }.map(\.id)
		#expect(ids.count == 2)
		try await context.repository.requestCommitTask(
			GitCommitTask(subject: "fix: update file", body: "", unitIDs: ids),
			expecting: input, at: context.url)
		#expect(
			try await output(["diff", "HEAD^", "HEAD", "--name-only"], in: context) == "file.txt\n")
		#expect(try await output(["diff", "--cached", "--name-only"], in: context) == "other.txt\n")
	}

	@Test
	func firstCommitAndBinaryChangesUseTheStagedContents() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "image.bin")
		let staged = Data([0, 1, 2, 3, 255])
		try staged.write(to: file)
		try await run(["add", "."], in: context)
		try Data([0, 9, 8, 7]).write(to: file)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		#expect(input.headHash == nil)
		#expect(input.units.count == 1)
		#expect(input.units.first?.hunk == nil)
		try await context.repository.requestCommitTask(
			GitCommitTask(subject: "feat: add binary", body: "", unitIDs: input.units.map(\.id)),
			expecting: input, at: context.url)
		let committed = try await context.runner.requestRun(
			arguments: ["show", "HEAD:image.bin"], at: context.url)
		#expect(committed.standardOutputData == staged)
		#expect(try Data(contentsOf: file) == Data([0, 9, 8, 7]))
	}

	@Test
	func changedIndexRejectsAStalePlanAndReleasesTheLock() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		try Data("planned\n".utf8).write(to: file)
		try await run(["add", "."], in: context)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		try Data("changed\n".utf8).write(to: file)
		try await run(["add", "."], in: context)
		await #expect(throws: GitCommitPlanError.self) {
			try await context.repository.requestCommitTask(
				GitCommitTask(subject: "feat: stale", body: "", unitIDs: input.units.map(\.id)),
				expecting: input, at: context.url)
		}
		#expect(
			!FileManager.default.fileExists(atPath: context.url.appending(path: ".git/index.lock").path))
		#expect(try await context.repository.requestCommitHistory(at: context.url).isEmpty)
		#expect(try await output(["show", ":file.txt"], in: context) == "changed\n")
	}

	@Test
	func failingCommitHookPreservesTheIndexAndHead() async throws {
		let context = try await makeContext()
		try Data("staged\n".utf8).write(to: context.url.appending(path: "file.txt"))
		try await run(["add", "."], in: context)
		let hook = context.url.appending(path: ".git/hooks/pre-commit")
		try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		let index = try Data(contentsOf: context.url.appending(path: ".git/index"))
		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestCommitTask(
				GitCommitTask(subject: "feat: rejected", body: "", unitIDs: input.units.map(\.id)),
				expecting: input, at: context.url)
		}
		#expect(try Data(contentsOf: context.url.appending(path: ".git/index")) == index)
		#expect(try await context.repository.requestCommitHistory(at: context.url).isEmpty)
		let files = try FileManager.default.contentsOfDirectory(
			atPath: context.url.appending(path: ".git").path)
		#expect(!files.contains { $0.hasPrefix("groves-commit-") || $0 == "index.lock" })
	}

	@Test
	func existingIndexLockIsPreservedWhenCommittingAPlan() async throws {
		let context = try await makeContext()
		try Data("staged\n".utf8).write(to: context.url.appending(path: "file.txt"))
		try await run(["add", "."], in: context)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		let lock = context.url.appending(path: ".git/index.lock")
		let contents = Data("another Git operation".utf8)
		try contents.write(to: lock)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestCommitTask(
				GitCommitTask(subject: "feat: locked", body: "", unitIDs: input.units.map(\.id)),
				expecting: input, at: context.url)
		}

		#expect(try Data(contentsOf: lock) == contents)
		#expect(try await context.repository.requestCommitHistory(at: context.url).isEmpty)
	}

	private func makeContext() async throws -> Context {
		let url = try makeTemporaryRepository(name: "GrovesCommitPlanningTests")
		let runner = GitProcessRunner(configuration: GitProcessConfiguration())
		let context = Context(url: url, runner: runner)
		try await run(["config", "user.name", "Groves Tests"], in: context)
		try await run(["config", "user.email", "tests@example.com"], in: context)
		return context
	}

	@Test
	func commitStyleExamplesComeFromCurrentHeadWithoutAuthorMetadata() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		try Data("base\n".utf8).write(to: file)
		try await run(["add", "."], in: context)
		try await run(["commit", "-m", "fix(api): 응답 형식 수정", "-m", "- 응답 필드 정리"], in: context)
		try await run(["switch", "-c", "other"], in: context)
		try await run(["commit", "--allow-empty", "-m", "unrelated branch style"], in: context)
		try await run(["switch", "-"], in: context)
		try Data("updated\n".utf8).write(to: file)
		try await run(["add", "."], in: context)
		let input = try await context.repository.requestCommitPlanInput(at: context.url)
		#expect(input.recentCommitMessages == ["fix(api): 응답 형식 수정\n\n- 응답 필드 정리"])
		#expect(!input.recentCommitMessages.joined().contains("tests@example.com"))
	}

	private func run(_ arguments: [String], in context: Context) async throws {
		_ = try await context.runner.requestRun(arguments: arguments, at: context.url)
	}

	private func output(_ arguments: [String], in context: Context) async throws -> String {
		try await context.runner.requestRun(arguments: arguments, at: context.url).standardOutput
	}
}
