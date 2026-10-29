import CoreGitCredential
import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitReferenceMutationTests {
	private final class Context: Sendable {
		let url: URL
		let runner: GitProcessRunner
		let repository: LocalGitRepository

		init(url: URL, runner: GitProcessRunner) {
			self.url = url
			self.runner = runner
			repository = LocalGitRepository(runner: runner)
		}

		deinit {
			try? FileManager.default.removeItem(at: url)
		}
	}

	@Test
	func invalidTagNamesNeverBecomeGitOptions() async throws {
		let context = try await makeContext()
		let hash = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["tag", hash, hash], in: context)
		for name in ["--delete", "--force", "-d", "invalid..name"] {
			do {
				try await context.repository.requestCreateTag(
					named: name, message: "", commitHash: hash, at: context.url)
				Issue.record("Expected invalid tag name rejection")
			} catch GitRepositoryError.commandFailed {}
			let tags = try await run(["tag", "--list"], in: context)
			#expect(tags == hash)
		}
	}

	@Test
	func createsLightweightAndAnnotatedTagsAtTheSelectedCommit() async throws {
		let context = try await makeContext()
		let first = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "second"], in: context)
		for (name, message) in [("release/light", ""), ("release/annotated", "Release notes")] {
			try await context.repository.requestCreateTag(
				named: name, message: message, commitHash: first, at: context.url)
			let target = try await run(["rev-parse", "refs/tags/\(name)^{}"], in: context)
			#expect(target == first)
		}
	}

	@Test
	func remoteBranchDeletionPreservesTheSameNamedTag() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["branch", "release"], in: context)
		_ = try await run(["tag", "release"], in: context)
		_ = try await run(
			[
				"push", "origin", "refs/heads/release:refs/heads/release",
				"refs/tags/release:refs/tags/release",
			],
			in: context)
		let branch = try #require(
			try await context.repository.requestRemotes(at: context.url).first?.branches.first {
				$0.name == "release"
			})

		try await context.repository.requestDeleteRemoteBranch(branch, at: context.url)

		let refs = try await context.runner.requestRun(
			arguments: ["for-each-ref", "--format=%(refname)"], at: remote)
		#expect(!refs.standardOutput.contains("refs/heads/release"))
		#expect(refs.standardOutput.contains("refs/tags/release"))
	}

	@Test
	func deletingAStaleRemoteBranchNeverDeletesATag() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["branch", "release"], in: context)
		_ = try await run(["tag", "release"], in: context)
		_ = try await run(
			[
				"push", "origin", "refs/heads/release:refs/heads/release",
				"refs/tags/release:refs/tags/release",
			],
			in: context)
		let branch = try #require(
			try await context.repository.requestRemotes(at: context.url).first?.branches.first {
				$0.name == "release"
			})
		_ = try await context.runner.requestRun(
			arguments: ["update-ref", "-d", "refs/heads/release"], at: remote)

		do {
			try await context.repository.requestDeleteRemoteBranch(branch, at: context.url)
		} catch GitRepositoryError.commandFailed {}

		let refs = try await context.runner.requestRun(
			arguments: ["for-each-ref", "--format=%(refname)"], at: remote)
		#expect(refs.standardOutput.contains("refs/tags/release"))
	}

	@Test
	func remoteNamesContainingSlashesKeepTheirBranches() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["remote", "add", "team/origin", remote.path], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)

		let remotes = try await context.repository.requestRemotes(at: context.url)
		let actual = try #require(remotes.first { $0.name == "team/origin" })
		#expect(actual.branches.map(\.name) == ["main"])
		#expect(actual.branches.map(\.remoteName) == ["team/origin"])
	}

	@Test
	func readingAndSavingAnInheritedPushURLKeepsItInherited() async throws {
		let context = try await makeContext()
		try await context.repository.requestAddRemote(
			named: "origin", fetchURL: "https://old.example/repo.git", pushURL: nil, at: context.url)
		let remote = try #require(try await context.repository.requestRemotes(at: context.url).first)
		#expect(remote.pushURL == nil)

		try await context.repository.requestUpdateRemote(
			named: remote.name, fetchURL: "https://new.example/repo.git", pushURL: remote.pushURL,
			at: context.url)

		let actual = try await run(["remote", "get-url", "--push", "origin"], in: context)
		#expect(actual == "https://new.example/repo.git")
	}

	@Test
	func multiplePushURLsAreNotPartiallyOverwritten() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		for url in ["https://first.example/repo.git", "https://second.example/repo.git"] {
			_ = try await run(["config", "--add", "remote.origin.pushurl", url], in: context)
		}
		let original = try Data(contentsOf: context.url.appending(path: ".git/config"))

		do {
			try await context.repository.requestUpdateRemote(
				named: "origin", fetchURL: "https://new.example/repo.git",
				pushURL: "https://replacement.example/repo.git", at: context.url)
			Issue.record("A single URL editor must not replace multiple destinations")
		} catch GitRepositoryError.commandFailed {}

		#expect(try Data(contentsOf: context.url.appending(path: ".git/config")) == original)
	}

	@Test
	func anExistingGitConfigurationLockIsPreserved() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		let config = context.url.appending(path: ".git/config")
		let lock = config.appendingPathExtension("lock")
		let original = try Data(contentsOf: config)
		try Data("another writer".utf8).write(to: lock)

		do {
			try await context.repository.requestUpdateRemote(
				named: "origin", fetchURL: "https://new.example/repo.git", pushURL: nil, at: context.url)
			Issue.record("Expected Git configuration lock rejection")
		} catch {}

		#expect(try Data(contentsOf: config) == original)
		#expect(try String(contentsOf: lock, encoding: .utf8) == "another writer")
	}

	@Test
	func cancellationAfterStagingFetchURLLeavesTheOriginalConfigurationUntouched() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		let config = context.url.appending(path: ".git/config")
		let original = try Data(contentsOf: config)
		let executable = context.url.appending(path: ".git/test-git")
		let marker = context.url.appending(path: ".git/push-update-started")
		let escapedMarker = marker.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		case " $* " in
		  *" --push "*|*" remote.origin.pushurl "*)
		    touch '\(escapedMarker)'
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
		let task = Task {
			try await repository.requestUpdateRemote(
				named: "origin", fetchURL: "https://new.example/repo.git",
				pushURL: "https://push.example/repo.git", at: context.url)
		}
		defer { task.cancel() }
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !FileManager.default.fileExists(atPath: marker.path), clock.now < deadline {
			try await Task.sleep(for: .milliseconds(5))
		}
		#expect(FileManager.default.fileExists(atPath: marker.path))
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(try Data(contentsOf: config) == original)
		#expect(!FileManager.default.fileExists(atPath: config.appendingPathExtension("lock").path))
		#expect(
			!FileManager.default.fileExists(atPath: config.appendingPathExtension("lock.lock").path))
	}

	@Test
	func configurationUpdatePreservesPermissionsAndUnrelatedSettings() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		_ = try await run(["config", "branch.feature.description", "Keep this setting"], in: context)
		let config = context.url.appending(path: ".git/config")
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)

		try await context.repository.requestUpdateRemote(
			named: "origin", fetchURL: "https://new.example/repo.git",
			pushURL: "https://push.example/repo.git", at: context.url)

		let value = try await run(["config", "branch.feature.description"], in: context)
		#expect(value == "Keep this setting")
		let attributes = try FileManager.default.attributesOfItem(atPath: config.path)
		#expect(attributes[.posixPermissions] as? Int == 0o600)
	}

	@Test
	func remoteURLsDefinedInAnIncludedFileAreNotSilentlyShadowed() async throws {
		let context = try await makeContext()
		let included = context.url.appending(path: ".git/remotes.config")
		try "[remote \"origin\"]\nurl = https://old.example/repo.git\n".write(
			to: included, atomically: true, encoding: .utf8)
		_ = try await run(["config", "include.path", "remotes.config"], in: context)
		let config = context.url.appending(path: ".git/config")
		let original = try Data(contentsOf: config)

		do {
			try await context.repository.requestUpdateRemote(
				named: "origin", fetchURL: "https://new.example/repo.git", pushURL: nil, at: context.url)
			Issue.record("Expected included configuration protection")
		} catch GitRepositoryError.commandFailed {}

		#expect(try Data(contentsOf: config) == original)
		let value = try await run(["remote", "get-url", "origin"], in: context)
		#expect(value == "https://old.example/repo.git")
	}

	@Test
	func anUnseenRemoteCommitPreventsBranchDeletion() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/release"], in: context)
		let branch = try #require(
			try await context.repository.requestRemotes(at: context.url).first?.branches.first)
		_ = try await run(["commit", "--allow-empty", "-m", "new remote commit"], in: context)
		let next = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/release"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestDeleteRemoteBranch(branch, at: context.url)
		}
		let current = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/release"], at: remote)
		#expect(current.standardOutput.trimmingCharacters(in: .newlines) == next)
	}

	@Test
	func branchLifecycleProtectsTheCurrentBranchAndUnmergedCommits() async throws {
		let context = try await makeContext()
		let original = try await run(["branch", "--show-current"], in: context)
		try await context.repository.requestCreateBranch(named: "feature/work", at: context.url)
		try await context.repository.requestRenameBranch(
			named: "feature/work", to: "feature/renamed", at: context.url)
		let current = try await run(["branch", "--show-current"], in: context)
		#expect(current == "feature/renamed")
		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestDeleteBranch(named: "feature/renamed", at: context.url)
		}
		_ = try await run(["commit", "--allow-empty", "-m", "unmerged work"], in: context)
		try await context.repository.requestSwitchBranch(named: original, at: context.url)
		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestDeleteBranch(named: "feature/renamed", at: context.url)
		}
		_ = try await run(["merge", "--ff-only", "refs/heads/feature/renamed"], in: context)
		try await context.repository.requestDeleteBranch(named: "feature/renamed", at: context.url)
		let branches = try await context.repository.requestBranches(at: context.url)
		#expect(!branches.contains { $0.name == "feature/renamed" })
	}

	@Test
	func trackingBranchCreationIsNotConfusedByASameNamedTag() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["remote", "add", "team/origin", remote.path], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["tag", "team/origin/main"], in: context)

		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "team/origin/main", at: context.url)

		let branches = try await context.repository.requestBranches(at: context.url)
		let branch = try #require(branches.first { $0.isCurrent })
		#expect(branch.name == "tracked")
		#expect(branch.upstream == "team/origin/main")
	}

	@Test
	func readsConfiguredRemoteURLsAndTrackingBranches() async throws {
		let context = try await makeContext()
		_ = try await run(["remote", "add", "origin", "https://example.com/Groves.git"], in: context)
		let head = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/main", head], in: context)

		let remote = try #require(try await context.repository.requestRemotes(at: context.url).first)

		#expect(remote.name == "origin")
		#expect(remote.fetchURL == "https://example.com/Groves.git")
		#expect(remote.pushURL == nil)
		#expect(remote.branches.map(\.fullName) == ["origin/main"])
	}

	@Test
	func remoteLifecyclePreservesExplicitAndInheritedPushURLs() async throws {
		let context = try await makeContext()
		try await context.repository.requestAddRemote(
			named: "origin", fetchURL: "https://example.com/fetch.git",
			pushURL: "ssh://example.com/push.git", at: context.url)
		let created = try #require(try await context.repository.requestRemotes(at: context.url).first)
		#expect(created.fetchURL == "https://example.com/fetch.git")
		#expect(created.pushURL == "ssh://example.com/push.git")

		try await context.repository.requestUpdateRemote(
			named: "origin", fetchURL: "https://example.com/updated.git", pushURL: nil, at: context.url)
		try await context.repository.requestRenameRemote(
			named: "origin", to: "upstream", at: context.url)
		let updated = try #require(try await context.repository.requestRemotes(at: context.url).first)
		#expect(updated.name == "upstream")
		#expect(updated.fetchURL == "https://example.com/updated.git")
		#expect(updated.pushURL == nil)

		try await context.repository.requestDeleteRemote(named: "upstream", at: context.url)
		let remotes = try await context.repository.requestRemotes(at: context.url)
		#expect(remotes.isEmpty)
	}

	@Test
	func pullingFromARemoteContainingSlashesUsesItsConfiguredNameAndUpstream() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["remote", "add", "team/origin", remote.path], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "team/origin/main", at: context.url)
		_ = try await run(["tag", "team/origin/main"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "remote change"], in: context)
		let next = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["reset", "--hard", "HEAD^"], in: context)

		let outcome = try await context.repository.requestPreparePull(at: context.url)

		#expect(outcome == .fastForwarded)
		let head = try await run(["rev-parse", "HEAD"], in: context)
		#expect(head == next)
	}

	@Test(arguments: [RepositoryPullResolution.merge, .rebase])
	func branchOperationsUseTheSelectedBranchInsteadOfASameNamedTag(
		resolution: RepositoryPullResolution
	) async throws {
		let context = try await makeContext()
		let original = try await run(["branch", "--show-current"], in: context)
		_ = try await run(["tag", "destination"], in: context)
		try await context.repository.requestCreateBranch(named: "destination", at: context.url)
		try Data("destination".utf8).write(to: context.url.appending(path: "destination.txt"))
		_ = try await run(["add", "destination.txt"], in: context)
		_ = try await run(["commit", "-m", "destination change"], in: context)
		let destination = try await run(["rev-parse", "HEAD"], in: context)
		try await context.repository.requestSwitchBranch(named: original, at: context.url)
		_ = try await run(["commit", "--allow-empty", "-m", "local change"], in: context)

		switch resolution {
		case .merge:
			try await context.repository.requestMergeBranch(named: "destination", at: context.url)
		case .rebase:
			try await context.repository.requestRebase(onto: "destination", at: context.url)
		}

		let ancestor = try await run(["merge-base", destination, "HEAD"], in: context)
		#expect(ancestor == destination)
	}

	@Test(arguments: [RepositoryPullResolution.merge, .rebase])
	func resolvingDivergedPullUsesTheTrackingRefInsteadOfASameNamedTag(
		resolution: RepositoryPullResolution
	) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["remote", "add", "team/origin", remote.path], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "team/origin/main", at: context.url)
		_ = try await run(["tag", "team/origin/main"], in: context)
		try Data("remote".utf8).write(to: context.url.appending(path: "remote.txt"))
		_ = try await run(["add", "remote.txt"], in: context)
		_ = try await run(["commit", "-m", "remote change"], in: context)
		let remoteHead = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["reset", "--hard", "HEAD^"], in: context)
		try Data("local".utf8).write(to: context.url.appending(path: "local.txt"))
		_ = try await run(["add", "local.txt"], in: context)
		_ = try await run(["commit", "-m", "local change"], in: context)
		let outcome = try await context.repository.requestPreparePull(at: context.url)
		guard case .diverged(let divergence) = outcome else {
			Issue.record("Expected diverged local and remote histories")
			return
		}

		try await context.repository.requestResolvePull(divergence, using: resolution, at: context.url)

		let ancestor = try await run(["merge-base", remoteHead, "HEAD"], in: context)
		#expect(ancestor == remoteHead)
	}

	@Test
	func symlinkedConfigurationIsUpdatedWithoutReplacingTheSymlink() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		let config = context.url.appending(path: ".git/config")
		let backing = context.url.appending(path: ".git/config.backing")
		try FileManager.default.moveItem(at: config, to: backing)
		try FileManager.default.createSymbolicLink(at: config, withDestinationURL: backing)

		try await context.repository.requestUpdateRemote(
			named: "origin", fetchURL: "https://new.example/repo.git", pushURL: nil, at: context.url)

		let destination = try FileManager.default.destinationOfSymbolicLink(atPath: config.path)
		#expect(destination == backing.path)
		let actual = try await run(["remote", "get-url", "origin"], in: context)
		#expect(actual == "https://new.example/repo.git")
	}

	private func makeContext() async throws -> Context {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "GrovesReferenceMutations-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		let identityURL = url.appending(path: ".git/app.config")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: identityURL),
			credentialStore: GitCredentialPersistingStub())
		let context = Context(url: url, runner: runner)
		_ = try await runner.requestRun(arguments: ["init", "--quiet"], at: url)
		try GitIdentityConfiguration(name: "Review", email: "review@example.com").save(to: identityURL)
		_ = try await runner.requestRun(
			arguments: ["commit", "--allow-empty", "-m", "initial"], at: url)
		return context
	}

	private func makeRemote(in context: Context) async throws -> URL {
		let remote = context.url.appending(path: ".git/test-remote.git")
		_ = try await context.runner.requestRun(
			arguments: ["init", "--bare", remote.path], at: context.url)
		_ = try await run(["remote", "add", "origin", remote.path], in: context)
		return remote
	}

	private func run(_ arguments: [String], in context: Context) async throws -> String {
		try await context.runner.requestRun(arguments: arguments, at: context.url)
			.standardOutput.trimmingCharacters(in: .newlines)
	}
}
