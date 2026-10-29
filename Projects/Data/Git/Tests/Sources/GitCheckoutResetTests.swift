import CoreGitCredential
import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitCheckoutResetTests {
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

	@Test(arguments: GitResetMode.allCases)
	func resetModesPreserveTheirIndexAndWorkingTreeSemantics(mode: GitResetMode) async throws {
		let context = try await makeContext()
		let initial = try await run(["rev-parse", "HEAD"], in: context)
		let tracked = context.url.appending(path: "tracked.txt")
		try Data("updated".utf8).write(to: tracked)
		_ = try await run(["add", "tracked.txt"], in: context)
		_ = try await run(["commit", "-m", "updated"], in: context)
		try Data("local".utf8).write(to: tracked)
		let untracked = context.url.appending(path: "unrelated.txt")
		try Data("keep".utf8).write(to: untracked)
		let expected = try await resetContext(in: context)

		try await context.repository.requestReset(
			to: initial, mode: mode, expecting: expected, at: context.url)

		let head = try await run(["rev-parse", "HEAD"], in: context)
		let indexed = try await run(["show", ":tracked.txt"], in: context)
		let contents = try String(contentsOf: tracked, encoding: .utf8)
		#expect(head == initial)
		#expect(indexed == (mode == .soft ? "updated" : "base"))
		#expect(contents == (mode == .hard ? "base" : "local"))
		#expect(try String(contentsOf: untracked, encoding: .utf8) == "keep")
	}

	@Test(arguments: ["same", "parent", "child", "ignored", "newline"])
	func hardResetRejectsUntrackedPathCollisionsWithoutChangingTheRepository(kind: String)
		async throws
	{
		let context = try await makeContext()
		let targetPath =
			kind == "parent" ? "folder/file.txt" : kind == "newline" ? "data\nfile" : "data"
		let targetFile = context.url.appending(path: targetPath)
		try FileManager.default.createDirectory(
			at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data("tracked target".utf8).write(to: targetFile)
		_ = try await run(["add", "--", targetPath], in: context)
		_ = try await run(["commit", "-m", "target file"], in: context)
		let target = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["rm", "--", targetPath], in: context)
		_ = try await run(["commit", "-m", "remove target file"], in: context)
		let privateFile: URL
		if kind == "child" {
			try FileManager.default.createDirectory(at: targetFile, withIntermediateDirectories: true)
			privateFile = targetFile.appending(path: "private.txt")
		} else if kind == "parent" {
			privateFile = context.url.appending(path: "folder")
		} else {
			privateFile = targetFile
		}
		try Data("private local work".utf8).write(to: privateFile)
		if kind == "ignored" {
			try Data("data\n".utf8).write(to: context.url.appending(path: ".git/info/exclude"))
		}
		let expected = try await resetContext(in: context)
		let index = try Data(contentsOf: context.url.appending(path: ".git/index"))

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestReset(
				to: target, mode: .hard, expecting: expected, at: context.url)
		}

		#expect(try String(contentsOf: privateFile, encoding: .utf8) == "private local work")
		#expect(try Data(contentsOf: context.url.appending(path: ".git/index")) == index)
		let actual = try await resetContext(in: context)
		#expect(actual == expected)
		try await context.repository.requestStage(path: "tracked.txt", at: context.url)
	}

	@Test(arguments: ["branch", "commit", "create", "tracking"])
	func everyCheckoutPathProtectsIgnoredLocalFiles(kind: String) async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "local.secret")
		try Data("tracked".utf8).write(to: file)
		_ = try await run(["add", "local.secret"], in: context)
		_ = try await run(["commit", "-m", "tracked target"], in: context)
		let target = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["branch", "target"], in: context)
		_ = try await run(["rm", "local.secret"], in: context)
		_ = try await run(["commit", "-m", "remove local secret"], in: context)
		_ = try await run(["remote", "add", "origin", "https://example.com/repo.git"], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/target", target], in: context)
		try Data("local.secret\n".utf8).write(to: context.url.appending(path: ".git/info/exclude"))
		try Data("private".utf8).write(to: file)
		let expected = try await resetContext(in: context)
		#expect(try await context.repository.requestWorkingTreeChanges(at: context.url).isEmpty)

		await #expect(throws: GitRepositoryError.self) {
			switch kind {
			case "branch":
				try await context.repository.requestSwitchBranch(named: "target", at: context.url)
			case "commit":
				try await context.repository.requestCheckoutCommit(target, at: context.url)
			case "create":
				try await context.repository.requestCreateBranch(
					named: "created", from: target, at: context.url)
			default:
				try await context.repository.requestCreateTrackingBranch(
					named: "created", tracking: "origin/target", at: context.url)
			}
		}

		#expect(try String(contentsOf: file, encoding: .utf8) == "private")
		let actual = try await resetContext(in: context)
		#expect(actual == expected)
		let branches = try await context.repository.requestBranches(at: context.url)
		#expect(!branches.contains { $0.name == "created" })
	}

	@Test
	func hardResetProtectsCaseInsensitivePathCollisions() async throws {
		let context = try await makeContext()
		let caseSensitive =
			try context.url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
			.volumeSupportsCaseSensitiveNames == true
		guard !caseSensitive else { return }
		let tracked = context.url.appending(path: "Data")
		try Data("tracked".utf8).write(to: tracked)
		_ = try await run(["add", "Data"], in: context)
		_ = try await run(["commit", "-m", "target file"], in: context)
		let target = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["rm", "Data"], in: context)
		_ = try await run(["commit", "-m", "remove target file"], in: context)
		let untracked = context.url.appending(path: "data")
		try Data("private".utf8).write(to: untracked)
		let expected = try await resetContext(in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestReset(
				to: target, mode: .hard, expecting: expected, at: context.url)
		}

		#expect(try String(contentsOf: untracked, encoding: .utf8) == "private")
		let actual = try await resetContext(in: context)
		#expect(actual == expected)
	}

	@Test
	func switchingADeletedLocalBranchDoesNotCreateATrackingBranch() async throws {
		let context = try await makeContext()
		let head = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["remote", "add", "origin", "https://example.com/repo.git"], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/feature", head], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestSwitchBranch(named: "feature", at: context.url)
		}

		let branches = try await context.repository.requestBranches(at: context.url)
		#expect(!branches.contains { $0.name == "feature" })
	}

	@Test(arguments: ["branch", "head"])
	func resetRejectsAChangedConfirmationContext(change: String) async throws {
		let context = try await makeContext()
		let expected = try await resetContext(in: context)
		if change == "branch" {
			try await context.repository.requestCreateBranch(named: "other", at: context.url)
		} else {
			_ = try await run(["commit", "--allow-empty", "-m", "new head"], in: context)
		}
		let current = try await resetContext(in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestReset(
				to: expected.headHash, mode: .hard, expecting: expected, at: context.url)
		}

		let actual = try await resetContext(in: context)
		#expect(actual == current)
	}

	@Test(arguments: GitResetMode.allCases)
	func aResetExcludesOtherWritersAcrossRepositoryInstances(mode: GitResetMode) async throws {
		let context = try await makeContext()
		let target = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "latest"], in: context)
		_ = try await run(["branch", "other"], in: context)
		let expected = try await resetContext(in: context)
		let marker = context.url.appending(path: ".git/reset-started")
		let release = context.url.appending(path: ".git/reset-release")
		let executable = context.url.appending(path: ".git/paused-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" reset "*)
		    touch '\(marker.path)'
		    while [ ! -f '\(release.path)' ]; do /bin/sleep 0.01; done
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let resetting = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					executableURL: executable, terminationGracePeriod: 0.01),
				credentialStore: GitCredentialPersistingStub()))
		let task = Task {
			try await resetting.requestReset(to: target, mode: mode, expecting: expected, at: context.url)
		}
		defer {
			try? Data().write(to: release)
			task.cancel()
		}
		try await waitForFile(marker)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestSwitchBranch(named: "other", at: context.url)
		}
		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestStage(path: "tracked.txt", at: context.url)
		}
		let alias = context.url.appending(path: ".git/repository-alias")
		try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: context.url)
		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestSwitchBranch(named: "other", at: alias)
		}
		let independent = try await makeContext()
		try await independent.repository.requestCreateBranch(named: "independent", at: independent.url)
		try Data().write(to: release)
		try await task.value

		let actual = try await resetContext(in: context)
		let other = try await run(["rev-parse", "refs/heads/other"], in: context)
		#expect(actual.headHash == target)
		#expect(actual.branchName == expected.branchName)
		#expect(other == expected.headHash)
		try await context.repository.requestSwitchBranch(named: "other", at: context.url)
	}

	@Test
	func cancellationReleasesTheRepositoryForTheNextCheckout() async throws {
		let context = try await makeContext()
		let expected = try await resetContext(in: context)
		_ = try await run(["branch", "other"], in: context)
		let marker = context.url.appending(path: ".git/reset-started")
		let executable = context.url.appending(path: ".git/cancellable-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" reset "*)
		    touch '\(marker.path)'
		    exec /bin/sleep 30
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let resetting = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					executableURL: executable, terminationGracePeriod: 0.01),
				credentialStore: GitCredentialPersistingStub()))
		let task = Task {
			try await resetting.requestReset(
				to: expected.headHash, mode: .soft, expecting: expected, at: context.url)
		}
		defer { task.cancel() }
		try await waitForFile(marker)

		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		try await context.repository.requestSwitchBranch(named: "other", at: context.url)

		let actual = try await resetContext(in: context)
		#expect(actual.branchName == "other")
		#expect(actual.headHash == expected.headHash)
	}

	private func makeContext() async throws -> Context {
		let url = FileManager.default.temporaryDirectory.appending(
			path: "GrovesCheckoutReset-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		let identity = url.appending(path: ".git/app.config")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: identity),
			credentialStore: GitCredentialPersistingStub())
		let context = Context(url: url, runner: runner)
		_ = try await run(["init", "--quiet"], in: context)
		try GitIdentityConfiguration(name: "Review", email: "review@example.com").save(to: identity)
		try Data("base".utf8).write(to: url.appending(path: "tracked.txt"))
		_ = try await run(["add", "tracked.txt"], in: context)
		_ = try await run(["commit", "-m", "initial"], in: context)
		return context
	}

	private func resetContext(in context: Context) async throws -> GitResetContext {
		let branch = try #require(
			try await context.repository.requestBranches(at: context.url).first(where: \.isCurrent))
		return GitResetContext(branchName: branch.name, headHash: branch.hash)
	}

	private func run(_ arguments: [String], in context: Context) async throws -> String {
		try await context.runner.requestRun(arguments: arguments, at: context.url).standardOutput
			.trimmingCharacters(in: .newlines)
	}

	private func waitForFile(_ url: URL) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !FileManager.default.fileExists(atPath: url.path) {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for the reset command")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
