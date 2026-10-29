import CoreGitCredential
import DataGit
import DomainGit
import DomainGitInterface
import Foundation
import Testing

struct RepositoryStashesUseCaseTests {
	private final class Context: Sendable {
		let url: URL
		let repository: LocalGitRepository
		let useCase: DefaultRepositoryStashesUseCase

		init(url: URL, repository: LocalGitRepository) {
			self.url = url
			self.repository = repository
			useCase = DefaultRepositoryStashesUseCase(
				repository: repository, content: DefaultRepositoryContentUseCase(repository: repository))
		}

		deinit { try? FileManager.default.removeItem(at: url) }
	}

	@Test
	func aNoOpPushReturnsTheCurrentUntrackedChanges() async throws {
		let context = try makeContext()
		let untracked = context.url.appending(path: "draft.txt")
		try Data("draft".utf8).write(to: untracked)

		let result = try await context.useCase.createStash(
			message: "draft", includeUntracked: false, at: context.url)

		#expect(result.outcome == .nothingToSave)
		#expect(result.snapshot.stashes.isEmpty)
		#expect(result.snapshot.changes.map(\.path) == ["draft.txt"])
		#expect(result.snapshot.changes.first?.workingTreeState == .untracked)
	}

	@Test(arguments: ["apply", "pop"])
	func aPartiallyAppliedStashReturnsTheActualWorkingTree(operation: String) async throws {
		let context = try makeContext()
		let untracked = context.url.appending(path: "draft.txt")
		try Data("saved draft".utf8).write(to: untracked)
		let selected = try await push(in: context)
		try Data("local draft".utf8).write(to: untracked)

		let result =
			try await
			(operation == "pop"
			? context.useCase.popStash(selected, at: context.url)
			: context.useCase.applyStash(selected, at: context.url))

		guard case .failed(let message) = result.outcome else {
			Issue.record("Expected a partial failure, got \(result.outcome)")
			return
		}
		#expect(!message.isEmpty)
		#expect(result.snapshot.stashes == [selected])
		#expect(Set(result.snapshot.changes.map(\.path)) == ["draft.txt", "tracked.txt"])
		#expect(
			result.snapshot.changes.contains { $0.path == "tracked.txt" && $0.hasWorkingTreeChange })
		#expect(!result.snapshot.operationState.hasConflicts)
		#expect(try String(contentsOf: untracked, encoding: .utf8) == "local draft")
	}

	@Test
	func aConflictedPopReturnsTheConflictsAndTheRetainedStash() async throws {
		let context = try makeContext()
		let selected = try await push(in: context)
		try Data("diverged\n".utf8).write(to: context.url.appending(path: "tracked.txt"))
		try runGit(["add", "tracked.txt"], at: context.url)
		try runGit(["commit", "-m", "diverge"], at: context.url)

		let result = try await context.useCase.popStash(selected, at: context.url)

		#expect(result.outcome == .conflicted)
		#expect(result.snapshot.operationState.hasConflicts)
		#expect(result.snapshot.stashes == [selected])
		#expect(result.snapshot.operationState.conflicts.map(\.path) == ["tracked.txt"])
	}

	@Test
	func aSuccessfulPopReturnsTheAppliedChangesWithoutTheStash() async throws {
		let context = try makeContext()
		let selected = try await push(in: context)

		let result = try await context.useCase.popStash(selected, at: context.url)

		#expect(result.outcome == .completed)
		#expect(result.snapshot.stashes.isEmpty)
		#expect(result.snapshot.changes.map(\.path) == ["tracked.txt"])
		#expect(!result.snapshot.operationState.hasConflicts)
		#expect(
			try String(contentsOf: context.url.appending(path: "tracked.txt"), encoding: .utf8)
				== "saved\n")
	}

	private func makeContext() throws -> Context {
		let url = FileManager.default.temporaryDirectory.appending(
			path: "GrovesStashesUseCase-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		let configuration = url.appending(path: ".git/app.config")
		let context = Context(
			url: url,
			repository: LocalGitRepository(
				configuration: GitProcessConfiguration(globalConfigurationURL: configuration)))
		try runGit(["init", "--quiet"], at: url)
		try GitIdentityConfiguration(name: "Review", email: "review@example.com").save(
			to: configuration)
		try Data("base\n".utf8).write(to: url.appending(path: "tracked.txt"))
		try runGit(["add", "tracked.txt"], at: url)
		try runGit(["commit", "-m", "initial"], at: url)
		return context
	}

	private func push(in context: Context) async throws -> GitStash {
		try Data("saved\n".utf8).write(to: context.url.appending(path: "tracked.txt"))
		let result = try await context.useCase.createStash(
			message: "saved", includeUntracked: true, at: context.url)
		#expect(result.outcome == .completed)
		return try #require(result.snapshot.stashes.first)
	}

	private func runGit(_ arguments: [String], at url: URL) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments =
			[
				"-C", url.path, "-c", "user.name=Review", "-c", "user.email=review@example.com",
				"-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
			] + arguments
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try process.run()
		process.waitUntilExit()
		try #require(process.terminationStatus == 0)
	}
}
