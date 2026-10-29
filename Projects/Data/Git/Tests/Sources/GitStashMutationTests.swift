import CoreGitCredential
import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitStashMutationTests {
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

	@Test(arguments: ["apply", "pop", "drop", "diff"])
	func aCachedStashDoesNotRetargetAfterANewerStashIsPushed(operation: String) async throws {
		let context = try await makeContext()
		let selected = try await push("selected-A", in: context)
		let newer = try await push("newer-B", in: context)
		switch operation {
		case "apply":
			try await context.repository.requestApplyStash(selected, at: context.url)
		case "pop":
			try await context.repository.requestPopStash(selected, at: context.url)
		case "drop":
			try await context.repository.requestDropStash(selected, at: context.url)
		default:
			let diff = try await context.repository.requestStashDiff(for: selected, at: context.url)
			#expect(diff.contains("+selected-A"))
		}
		let remaining = try await context.repository.requestStashes(at: context.url)
		#expect(remaining.contains { $0.hash == newer.hash })
		#expect(
			remaining.contains { $0.hash == selected.hash } == (operation != "pop" && operation != "drop")
		)
		if operation == "apply" || operation == "pop" {
			let contents = try String(
				contentsOf: context.url.appending(path: "tracked.txt"), encoding: .utf8)
			#expect(contents == "selected-A\n")
		}
	}

	@Test
	func droppingAStashCannotInterleaveWithAnActivePop() async throws {
		let context = try await makeContext()
		let oldest = try await push("oldest-C", in: context)
		let selected = try await push("selected-B", in: context)
		let top = try await push("top-A", in: context)
		let stashes = try await context.repository.requestStashes(at: context.url)
		let selectedAtCurrentIndex = try #require(stashes.first { $0.hash == selected.hash })
		let marker = context.url.appending(path: ".git/pop-started")
		let release = context.url.appending(path: ".git/pop-release")
		let executable = context.url.appending(path: ".git/paused-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" stash pop "*|*" stash apply "*)
		    touch '\(marker.path)'
		    while [ ! -f '\(release.path)' ]; do /bin/sleep 0.01; done
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(executableURL: executable),
				credentialStore: GitCredentialPersistingStub()))
		let task = Task {
			try await repository.requestPopStash(selectedAtCurrentIndex, at: context.url)
		}
		defer {
			try? Data().write(to: release)
			task.cancel()
		}
		try await waitForFile(marker)
		await #expect(throws: GitRepositoryError.self) {
			try await repository.requestDropStash(top, at: context.url)
		}
		try Data().write(to: release)
		#expect(try await task.value == .completed)

		let remaining = try await context.repository.requestStashes(at: context.url)
		let contents = try String(
			contentsOf: context.url.appending(path: "tracked.txt"), encoding: .utf8)
		#expect(remaining.contains { $0.hash == oldest.hash })
		#expect(contents == "selected-B\n")
	}

	@Test(arguments: ["apply", "pop", "drop"])
	func aRemovedStashCannotTargetTheEntryThatReplacesItsIndex(operation: String) async throws {
		let context = try await makeContext()
		let selected = try await push("removed", in: context)
		try await context.repository.requestDropStash(selected, at: context.url)
		let replacement = try await push("replacement", in: context)

		await #expect(throws: GitRepositoryError.self) {
			switch operation {
			case "apply":
				try await context.repository.requestApplyStash(selected, at: context.url)
			case "pop":
				try await context.repository.requestPopStash(selected, at: context.url)
			default:
				try await context.repository.requestDropStash(selected, at: context.url)
			}
		}

		#expect(try await context.repository.requestStashes(at: context.url) == [replacement])
		#expect(try await context.repository.requestWorkingTreeChanges(at: context.url).isEmpty)
	}

	@Test
	func excludingUntrackedFilesReportsNothingToSave() async throws {
		let context = try await makeContext()
		let untracked = context.url.appending(path: "draft.txt")
		try Data("private draft".utf8).write(to: untracked)

		let excluded = try await context.repository.requestCreateStash(
			message: "draft", includeUntracked: false, at: context.url)

		#expect(excluded == .nothingToSave)
		#expect(try await context.repository.requestStashes(at: context.url).isEmpty)
		#expect(try String(contentsOf: untracked, encoding: .utf8) == "private draft")

		let included = try await context.repository.requestCreateStash(
			message: "draft", includeUntracked: true, at: context.url)

		#expect(included == .completed)
		#expect(try await context.repository.requestStashes(at: context.url).count == 1)
		#expect(!FileManager.default.fileExists(atPath: untracked.path))
	}

	@Test(arguments: ["apply", "pop"])
	func anUntrackedCollisionReportsPartialFailureAndKeepsTheStash(operation: String) async throws {
		let context = try await makeContext()
		let untracked = context.url.appending(path: "draft.txt")
		try Data("saved draft".utf8).write(to: untracked)
		let selected = try await push("saved tracked", in: context)
		try Data("local draft".utf8).write(to: untracked)

		let outcome =
			try await
			(operation == "pop"
			? context.repository.requestPopStash(selected, at: context.url)
			: context.repository.requestApplyStash(selected, at: context.url))

		guard case .failed(let message) = outcome else {
			Issue.record("Expected a partial failure, got \(outcome)")
			return
		}
		#expect(!message.isEmpty)
		#expect(try String(contentsOf: untracked, encoding: .utf8) == "local draft")
		#expect(
			try String(contentsOf: context.url.appending(path: "tracked.txt"), encoding: .utf8)
				== "saved tracked\n")
		#expect(
			try await context.repository.requestOperationState(at: context.url).hasConflicts == false)
		#expect(try await context.repository.requestStashes(at: context.url) == [selected])
	}

	@Test
	func aConflictedPopKeepsItsStashAndReportsConflicts() async throws {
		let context = try await makeContext()
		let selected = try await push("saved tracked", in: context)
		try Data("committed change\n".utf8).write(to: context.url.appending(path: "tracked.txt"))
		_ = try await run(["add", "tracked.txt"], in: context)
		_ = try await run(["commit", "-m", "diverge"], in: context)

		let outcome = try await context.repository.requestPopStash(selected, at: context.url)

		#expect(outcome == .conflicted)
		#expect(try await context.repository.requestOperationState(at: context.url).hasConflicts)
		#expect(try await context.repository.requestStashes(at: context.url) == [selected])
	}

	@Test
	func applyingAStashRestoresTheIndexAndWorkingTreeSeparately() async throws {
		let context = try await makeContext()
		let tracked = context.url.appending(path: "tracked.txt")
		try Data("staged\n".utf8).write(to: tracked)
		_ = try await run(["add", "tracked.txt"], in: context)
		try Data("unstaged\n".utf8).write(to: tracked)
		try await context.repository.requestCreateStash(message: "split", at: context.url)
		let selected = try #require(try await context.repository.requestStashes(at: context.url).first)

		let outcome = try await context.repository.requestApplyStash(selected, at: context.url)

		#expect(outcome == .completed)
		#expect(try await run(["show", ":tracked.txt"], in: context) == "staged")
		#expect(try String(contentsOf: tracked, encoding: .utf8) == "unstaged\n")
		#expect(try await context.repository.requestStashes(at: context.url) == [selected])
	}

	@Test
	func duplicateObjectsHaveUniqueIDsAndDropUsesTheSelectedLabel() async throws {
		let context = try await makeContext()
		let selected = try await push("selected", in: context)
		_ = try await push("intermediate", in: context)
		_ = try await run(["stash", "store", "--message", "copy", selected.hash], in: context)
		_ = try await push("intermediate-2", in: context)
		_ = try await run(["stash", "store", "--message", "copy", selected.hash], in: context)
		let before = try await context.repository.requestStashes(at: context.url)
		#expect(before.count == 5)
		#expect(Set(before.map(\.id)).count == 5)
		let newer = try await push("newer", in: context)

		let outcome = try await context.repository.requestDropStash(selected, at: context.url)

		#expect(outcome == .completed)
		let after = try await context.repository.requestStashes(at: context.url)
		#expect(after.count == 5)
		#expect(after.first?.hash == newer.hash)
		#expect(after.filter { $0.subject == "copy" }.count == 2)
		#expect(!after.contains { $0.subject == selected.subject })
	}

	@Test(arguments: [false, true])
	func imageDiffUsesTheSelectedObjectAfterItsIndexChanges(untracked: Bool) async throws {
		let context = try await makeContext()
		let image = context.url.appending(path: "image.png")
		let original = Data([0, 1, 2])
		let saved = Data([0, 3, 4])
		if !untracked {
			try original.write(to: image)
			_ = try await run(["add", "image.png"], in: context)
			_ = try await run(["commit", "-m", "image"], in: context)
		}
		try saved.write(to: image)
		let selected = try await push("selected", in: context)
		try Data([0, 5, 6]).write(to: image)
		_ = try await push("newer", in: context)

		let diff = try await context.repository.requestStashImageDiff(
			for: selected, path: "image.png", previousPath: nil, at: context.url)

		#expect(diff.before == (untracked ? nil : original))
		#expect(diff.after == saved)
	}

	@Test
	func cancellingAfterApplyKeepsTheStashAndReleasesTheMutationGuard() async throws {
		let context = try await makeContext()
		let selected = try await push("saved", in: context)
		let marker = context.url.appending(path: ".git/drop-started")
		let executable = context.url.appending(path: ".git/cancellable-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" stash drop "*)
		    touch '\(marker.path)'
		    exec /bin/sleep 30
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					executableURL: executable, terminationGracePeriod: 0.01),
				credentialStore: GitCredentialPersistingStub()))
		let task = Task { try await repository.requestPopStash(selected, at: context.url) }
		defer { task.cancel() }
		try await waitForFile(marker)

		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }

		#expect(try await context.repository.requestStashes(at: context.url) == [selected])
		#expect(
			try String(contentsOf: context.url.appending(path: "tracked.txt"), encoding: .utf8)
				== "saved\n")
		try await context.repository.requestStage(path: "tracked.txt", at: context.url)
	}

	private func makeContext() async throws -> Context {
		let url = FileManager.default.temporaryDirectory.appending(
			path: "GrovesStashMutation-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		let identity = url.appending(path: ".git/review.config")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: identity),
			credentialStore: GitCredentialPersistingStub())
		let context = Context(url: url, runner: runner)
		_ = try await runner.requestRun(arguments: ["init", "--quiet"], at: url)
		try GitIdentityConfiguration(name: "Review", email: "review@example.com").save(to: identity)
		try Data("base\n".utf8).write(to: url.appending(path: "tracked.txt"))
		_ = try await runner.requestRun(arguments: ["add", "tracked.txt"], at: url)
		_ = try await runner.requestRun(arguments: ["commit", "-m", "initial"], at: url)
		return context
	}

	private func push(_ contents: String, in context: Context) async throws -> GitStash {
		try Data("\(contents)\n".utf8).write(to: context.url.appending(path: "tracked.txt"))
		try await context.repository.requestCreateStash(message: contents, at: context.url)
		return try #require(try await context.repository.requestStashes(at: context.url).first)
	}

	private func run(_ arguments: [String], in context: Context) async throws -> String {
		try await context.runner.requestRun(arguments: arguments, at: context.url).standardOutput
			.trimmingCharacters(in: .newlines)
	}

	private func waitForFile(_ url: URL) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while !FileManager.default.fileExists(atPath: url.path) {
			guard ContinuousClock.now < deadline else {
				Issue.record("Timed out waiting for the stash command")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
