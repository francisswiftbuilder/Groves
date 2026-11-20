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
			repository = LocalGitRepository(runner: runner) { originals in
				try FileManager.default.moveItem(
					at: originals, to: url.appending(path: ".git/test-discard-archive"))
			}
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

	@Test(arguments: [false, true])
	func tagDeletionCannotDeleteAReplacementWithTheSameName(annotated: Bool) async throws {
		let context = try await makeContext()
		let original = try await run(["rev-parse", "HEAD"], in: context)
		let arguments = annotated ? ["tag", "-a", "-m", "old", "release"] : ["tag", "release"]
		_ = try await run(arguments, in: context)
		let reviewed = try #require(try await context.repository.requestTags(at: context.url).first)
		if !annotated {
			_ = try await run(["commit", "--allow-empty", "-m", "new target"], in: context)
		}
		_ = try await run(
			annotated ? ["tag", "-f", "-a", "-m", "new", "release"] : ["tag", "-f", "release"],
			in: context)
		let replacement = try await run(["rev-parse", "refs/tags/release"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestDeleteTag(reviewed, at: context.url)
		}

		#expect(reviewed.objectHash != replacement)
		#expect(try await run(["rev-parse", "refs/tags/release"], in: context) == replacement)
		if annotated {
			#expect(try await run(["rev-parse", "refs/tags/release^{}"], in: context) == original)
		}
	}

	@Test(arguments: ["delete", "force", "setUpstream"])
	func reviewedPushUsesTheSameRemoteAfterItsAliasIsRepointed(operation: String) async throws {
		let context = try await makeContext()
		let approved = try await makeRemote(in: context, name: "approved=source.git")
		let replacement = context.url.appending(path: ".git/replacement.git")
		_ = try await run(["init", "--bare", replacement.path], in: context)
		let original = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "-u", "origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["push", replacement.path, "HEAD:refs/heads/main"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "reviewed work"], in: context)
		let setsUpstream = operation == "setUpstream"
		if setsUpstream { _ = try await run(["switch", "-c", "untracked"], in: context) }
		let branch = try await requestCurrentBranch(in: context)
		let remotes = try await context.repository.requestRemotes(at: context.url)
		let reviewed = try #require(remotes.first?.branches.first { $0.name == "main" })
		let marker = context.url.appending(path: ".git/push-repointed")
		let executable = context.url.appending(path: ".git/concurrent-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" push "*)
		    /usr/bin/git -C '\(context.url.path)' remote set-url origin '\(replacement.path)' || exit 91
		    touch '\(marker.path)'
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					executableURL: executable,
					globalConfigurationURL: context.url.appending(path: ".git/app.config"))))

		switch operation {
		case "force":
			try await repository.requestForcePush(
				.upstream(), expecting: branch, remotes: remotes, at: context.url)
		case "setUpstream":
			do {
				try await repository.requestForcePush(
					.setUpstream(remoteName: "origin", branchName: branch.name), expecting: branch,
					remotes: remotes, at: context.url)
				Issue.record("Expected the changed remote to prevent upstream configuration")
			} catch GitRepositoryError.commandFailed(let message) {
				#expect(message.contains("The push completed"))
			}
			#expect(try await requestCurrentBranch(in: context).upstream == nil)
		default:
			try await repository.requestDeleteRemoteBranch(reviewed, at: context.url)
		}

		#expect(FileManager.default.fileExists(atPath: marker.path))
		let pushedBranch = setsUpstream ? branch.name : "main"
		let refs = ["for-each-ref", "--format=%(objectname)", "refs/heads/\(pushedBranch)"]
		let unaffected = try await context.runner.requestRun(arguments: refs, at: replacement)
		let updated = try await context.runner.requestRun(arguments: refs, at: approved)
		#expect(unaffected.standardOutput == (setsUpstream ? "" : original + "\n"))
		#expect(updated.standardOutput == (operation == "delete" ? "" : branch.hash + "\n"))

		await #expect(throws: GitRepositoryError.self) {
			if operation == "delete" {
				try await repository.requestDeleteRemoteBranch(reviewed, at: context.url)
			} else {
				let target: GitPushTarget =
					setsUpstream ? .setUpstream(remoteName: "origin", branchName: branch.name) : .upstream()
				try await repository.requestForcePush(
					target, expecting: branch, remotes: remotes, at: context.url)
			}
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
	func configurationUpdatesPreserveUnrelatedNestedLocks() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		let config = context.url.appending(path: ".git/config")
		let lock = config.appendingPathExtension("lock.lock")
		let contents = Data("another configuration writer".utf8)
		try contents.write(to: lock)

		try await context.repository.requestUpdateRemote(
			named: "origin", fetchURL: "https://new.example/repo.git", pushURL: nil, at: context.url)

		#expect(try Data(contentsOf: lock) == contents)
		#expect(
			try await run(["remote", "get-url", "origin"], in: context) == "https://new.example/repo.git")
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
		    previous=''
		    for argument in "$@"; do
		      if [ "$previous" = '--file' ]; then touch "$argument.lock"; fi
		      previous="$argument"
		    done
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
		let files = try FileManager.default.contentsOfDirectory(
			atPath: config.deletingLastPathComponent().path)
		#expect(!files.contains { $0.hasPrefix("pluminon-config-") })
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
		_ = try await run(["remote", "add", "origin", "https://example.com/Pluminon.git"], in: context)
		let head = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/main", head], in: context)

		let remote = try #require(try await context.repository.requestRemotes(at: context.url).first)

		#expect(remote.name == "origin")
		#expect(remote.fetchURL == "https://example.com/Pluminon.git")
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

		let outcome = try await context.repository.requestPreparePull(
			expecting: requestCurrentBranch(in: context), at: context.url)

		#expect(outcome == .fastForwarded)
		let head = try await run(["rev-parse", "HEAD"], in: context)
		#expect(head == next)
	}

	@Test
	func pullRejectsABranchSwitchEvenWithTheSameHeadAndUpstream() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "displayed", tracking: "origin/main", at: context.url)
		let displayed = try await requestCurrentBranch(in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "actual", tracking: "origin/main", at: context.url)

		await #expect(throws: GitRepositoryError.self) {
			_ = try await context.repository.requestPreparePull(expecting: displayed, at: context.url)
		}
		let actual = try await requestCurrentBranch(in: context)
		#expect(actual.name == "actual")
		#expect(actual.hash == displayed.hash)
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
		let outcome = try await context.repository.requestPreparePull(
			expecting: requestCurrentBranch(in: context), at: context.url)
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

	@Test(arguments: [false, true])
	func pushesToADifferentlyNamedUpstreamWithoutChangingOtherReferences(force: Bool) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["remote", "add", "team/origin", remote.path], in: context)
		_ = try await run(["push", "team/origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "team/origin/main", at: context.url)
		_ = try await run(["tag", "tracked"], in: context)
		_ = try await run(["config", "push.default", "simple"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "local change"], in: context)
		let head = try await run(["rev-parse", "HEAD"], in: context)

		if force {
			try await context.repository.requestForcePush(
				.upstream(), expecting: try await requestCurrentBranch(in: context),
				remotes: context.repository.requestRemotes(at: context.url), at: context.url)
		} else {
			try await context.repository.requestPush(.upstream(), at: context.url)
		}

		let references = try await context.runner.requestRun(
			arguments: ["for-each-ref", "--format=%(refname) %(objectname)"], at: remote)
		#expect(references.standardOutput == "refs/heads/main \(head)\n")
		let branch = try #require(
			try await context.repository.requestBranches(at: context.url).first(where: \.isCurrent))
		#expect(branch.aheadCount == 0)
		#expect(branch.upstream == "team/origin/main")
	}

	@Test(arguments: [false, true])
	func firstPushSelectsTheBranchInsteadOfASameNamedTag(force: Bool) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		try await context.repository.requestCreateBranch(named: "release", at: context.url)
		_ = try await run(["tag", "release"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "release change"], in: context)
		let head = try await run(["rev-parse", "HEAD"], in: context)
		let target = GitPushTarget.setUpstream(remoteName: "origin", branchName: "release")

		if force {
			try await context.repository.requestForcePush(
				target, expecting: try await requestCurrentBranch(in: context),
				remotes: context.repository.requestRemotes(at: context.url), at: context.url)
		} else {
			try await context.repository.requestPush(target, at: context.url)
		}

		let references = try await context.runner.requestRun(
			arguments: ["for-each-ref", "--format=%(refname) %(objectname)"], at: remote)
		#expect(references.standardOutput == "refs/heads/release \(head)\n")
		let upstream = try await run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: context)
		#expect(upstream == "origin/release")
	}

	@Test(arguments: ["branch.tracked.pushRemote", "remote.pushDefault", nil] as [String?])
	func pushRemoteOverridesPreserveTheFetchUpstream(key: String?) async throws {
		let context = try await makeContext()
		let upstreamRemote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		let original = try await run(["rev-parse", "HEAD"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/main", at: context.url)
		let pushRemote = context.url.appending(path: ".git/fork.git")
		_ = try await run(["init", "--bare", pushRemote.path], in: context)
		_ = try await run(["remote", "add", "fork", pushRemote.path], in: context)
		if let key {
			_ = try await run(["config", key, "fork"], in: context)
		}
		_ = try await run(["commit", "--allow-empty", "-m", "fork change"], in: context)
		let head = try await run(["rev-parse", "HEAD"], in: context)

		try await context.repository.requestPush(
			.upstream(branchName: "tracked", remoteName: key == nil ? "fork" : nil), at: context.url)

		let upstreamHead = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: upstreamRemote)
		#expect(upstreamHead.standardOutput.trimmingCharacters(in: .newlines) == original)
		let references = try await context.runner.requestRun(
			arguments: ["for-each-ref", "--format=%(refname) %(objectname)"], at: pushRemote)
		#expect(references.standardOutput == "refs/heads/tracked \(head)\n")
		let upstream = try await run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: context)
		#expect(upstream == "origin/main")
	}

	@Test
	func forcePushRejectsUnseenCommitsOnADifferentlyNamedUpstream() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		let original = try await run(["rev-parse", "HEAD"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/main", at: context.url)
		_ = try await run(["commit", "--allow-empty", "-m", "unseen remote change"], in: context)
		let remoteHead = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["reset", "--hard", original], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/main", original], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "local rewrite"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestForcePush(
				.upstream(), expecting: try await requestCurrentBranch(in: context),
				remotes: context.repository.requestRemotes(at: context.url), at: context.url)
		}

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: remote)
		#expect(actual.standardOutput.trimmingCharacters(in: .newlines) == remoteHead)
	}

	@Test
	func backgroundFetchUpdatesTrackingStateWithoutChangingLocalWork() async throws {
		let context = try await makeContext()
		_ = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		let original = try await run(["rev-parse", "HEAD"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/main", at: context.url)
		_ = try await run(["commit", "--allow-empty", "-m", "remote change"], in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(["reset", "--hard", original], in: context)
		_ = try await run(["update-ref", "refs/remotes/origin/main", original], in: context)
		try Data("local work".utf8).write(to: context.url.appending(path: "Local.txt"))
		let changes = try await context.repository.requestWorkingTreeChanges(at: context.url)

		try await context.repository.requestFetchAll(at: context.url, allowsUserInteraction: false)

		let branch = try #require(
			try await context.repository.requestBranches(at: context.url).first(where: \.isCurrent))
		#expect(branch.hash == original)
		#expect(branch.behindCount == 1)
		#expect(try await context.repository.requestWorkingTreeChanges(at: context.url) == changes)
		#expect(
			try String(contentsOf: context.url.appending(path: "Local.txt"), encoding: .utf8)
				== "local work")
	}

	@Test(arguments: ["first.txt", "file[1].txt", "파일.txt"], [false, true])
	func unbornUnstagePreservesWorkingFilesAndUnrelatedStagedChanges(
		path: String, editsWorkingFile: Bool
	) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let repository = LocalGitRepository()
		let selected = url.appending(path: path)
		try Data("staged".utf8).write(to: selected)
		try Data("unrelated".utf8).write(to: url.appending(path: "unrelated.txt"))
		try await repository.requestStage(path: path, at: url)
		try await repository.requestStage(path: "unrelated.txt", at: url)
		let expected = editsWorkingFile ? "new working content" : "staged"
		try Data(expected.utf8).write(to: selected)
		let change = try #require(
			try await repository.requestWorkingTreeChanges(at: url).first { $0.path == path })

		try await repository.requestUnstage(change: change, at: url)

		#expect(try String(contentsOf: selected, encoding: .utf8) == expected)
		let changes = try await repository.requestWorkingTreeChanges(at: url)
		#expect(changes.filter(\.isStaged).map(\.path) == ["unrelated.txt"])
		#expect(changes.first { $0.path == path }?.workingTreeState == .untracked)
	}

	@Test(arguments: [false, true])
	func unstageRenamesRestoresBothIndexPathsWithoutTouchingWorkingFiles(recreatesSource: Bool)
		async throws
	{
		let context = try await makeContext()
		let original = String(repeating: "original\n", count: 20)
		try Data(original.utf8).write(to: context.url.appending(path: "old.txt"))
		_ = try await run(["add", "old.txt"], in: context)
		_ = try await run(["commit", "-m", "add original"], in: context)
		_ = try await run(["mv", "old.txt", "new.txt"], in: context)
		let newContents = original + "new edit\n"
		try Data(newContents.utf8).write(to: context.url.appending(path: "new.txt"))
		if recreatesSource {
			try Data("separate new work".utf8).write(to: context.url.appending(path: "old.txt"))
		}
		try Data("unrelated".utf8).write(to: context.url.appending(path: "unrelated.txt"))
		_ = try await run(["add", "unrelated.txt"], in: context)
		let change = try #require(
			try await context.repository.requestWorkingTreeChanges(at: context.url).first {
				$0.path == "new.txt"
			})
		#expect(change.previousPath == "old.txt")

		try await context.repository.requestUnstage(change: change, at: context.url)

		let changes = try await context.repository.requestWorkingTreeChanges(at: context.url)
		#expect(changes.filter(\.isStaged).map(\.path) == ["unrelated.txt"])
		#expect(
			try await run(["show", ":old.txt"], in: context) == original.trimmingCharacters(in: .newlines)
		)
		#expect(
			try String(contentsOf: context.url.appending(path: "new.txt"), encoding: .utf8) == newContents
		)
		if recreatesSource {
			#expect(
				try String(contentsOf: context.url.appending(path: "old.txt"), encoding: .utf8)
					== "separate new work")
		}
	}

	@Test
	func discardOfARenamedFilePreservesTheRecreatedSourceAndOtherFiles() async throws {
		let context = try await makeContext()
		let original = String(repeating: "original\n", count: 20)
		try Data(original.utf8).write(to: context.url.appending(path: "old.txt"))
		_ = try await run(["add", "old.txt"], in: context)
		_ = try await run(["commit", "-m", "add original"], in: context)
		_ = try await run(["mv", "old.txt", "new.txt"], in: context)
		try Data((original + "discard this edit\n").utf8).write(
			to: context.url.appending(path: "new.txt"))
		try Data("keep recreated source".utf8).write(to: context.url.appending(path: "old.txt"))
		try Data("keep unrelated file".utf8).write(to: context.url.appending(path: "other.txt"))
		let change = try #require(
			try await context.repository.requestWorkingTreeChanges(at: context.url).first {
				$0.path == "new.txt"
			})

		let discard = try await context.repository.requestDiscardContext(for: [change], at: context.url)
		try await context.repository.requestDiscard(discard, at: context.url)

		#expect(
			try String(contentsOf: context.url.appending(path: "new.txt"), encoding: .utf8) == original)
		#expect(
			try String(contentsOf: context.url.appending(path: "old.txt"), encoding: .utf8)
				== "keep recreated source")
		#expect(
			try String(contentsOf: context.url.appending(path: "other.txt"), encoding: .utf8)
				== "keep unrelated file")
		let staged = try await context.repository.requestWorkingTreeChanges(at: context.url).filter(
			\.isStaged)
		#expect(staged.count == 1)
		#expect(staged.first?.indexState == .renamed)
		let archived = context.url.appending(path: ".git/test-discard-archive/new.txt")
		#expect(try String(contentsOf: archived, encoding: .utf8) == original + "discard this edit\n")
	}

	@Test
	func discardOfAnUntrackedFileArchivesItsContents() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "draft.txt")
		try Data("recoverable draft".utf8).write(to: file)
		let changes = try await context.repository.requestWorkingTreeChanges(at: context.url)
		let discard = try await context.repository.requestDiscardContext(for: changes, at: context.url)

		try await context.repository.requestDiscard(discard, at: context.url)

		#expect(!FileManager.default.fileExists(atPath: file.path))
		let archived = context.url.appending(path: ".git/test-discard-archive/draft.txt")
		#expect(try String(contentsOf: archived, encoding: .utf8) == "recoverable draft")
	}

	@Test
	func discardRejectsAFileReplacedByADirectoryAndRestoresOtherSelectedFiles() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "first.txt")
		let replaced = context.url.appending(path: "second.txt")
		try Data("first draft".utf8).write(to: file)
		try Data("second draft".utf8).write(to: replaced)
		let changes = try await context.repository.requestWorkingTreeChanges(at: context.url)
		let discard = try await context.repository.requestDiscardContext(for: changes, at: context.url)
		try FileManager.default.moveItem(at: replaced, to: context.url.appending(path: "original.txt"))
		try FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: false)
		let child = replaced.appending(path: "new.txt")
		try Data("new work".utf8).write(to: child)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestDiscard(discard, at: context.url)
		}
		#expect(try String(contentsOf: file, encoding: .utf8) == "first draft")
		#expect(try String(contentsOf: child, encoding: .utf8) == "new work")
	}

	@Test
	func discardPreservesAnEditSavedAfterTheOriginalWasCaptured() async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "tracked.txt")
		try Data("index".utf8).write(to: file)
		_ = try await run(["add", "tracked.txt"], in: context)
		try Data("reviewed edit".utf8).write(to: file)
		let changes = try await context.repository.requestWorkingTreeChanges(at: context.url)
		let discard = try await context.repository.requestDiscardContext(for: changes, at: context.url)
		let executable = context.url.appending(path: ".git/test-git")
		let escapedPath = file.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		case " $* " in
		  *" hash-object "*"/pluminon-discard-"*) printf 'new edit' > '\(escapedPath)' ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(executableURL: executable),
				credentialStore: GitCredentialPersistingStub()))

		await #expect(throws: GitRepositoryError.self) {
			try await repository.requestDiscard(discard, at: context.url)
		}
		#expect(try String(contentsOf: file, encoding: .utf8) == "new edit")
		let transactions = try FileManager.default.contentsOfDirectory(
			at: context.url.appending(path: ".git"), includingPropertiesForKeys: nil)
		let transaction = try #require(
			transactions.first { $0.lastPathComponent.hasPrefix("pluminon-discard-") })
		let originals = try FileManager.default.contentsOfDirectory(
			at: transaction, includingPropertiesForKeys: nil)
		let archive = try #require(originals.first)
		#expect(
			try String(contentsOf: archive.appending(path: "tracked.txt"), encoding: .utf8)
				== "reviewed edit")
	}

	@Test(arguments: [GitDiffHunkAction.stage, .unstage, .discard])
	func staleHunkActionsPreserveNewWorkingAndIndexContents(action: GitDiffHunkAction) async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		try Data("base\n".utf8).write(to: file)
		_ = try await run(["add", "file.txt"], in: context)
		_ = try await run(["commit", "-m", "base file"], in: context)
		try Data("reviewed\n".utf8).write(to: file)
		if action == .unstage { _ = try await run(["add", "file.txt"], in: context) }
		let source: GitDiffSource = action == .unstage ? .staged : .unstaged
		let change = try #require(
			try await context.repository.requestWorkingTreeChanges(at: context.url).first)
		let displayed = try await context.repository.requestDiff(
			for: change, source: source, options: GitDiffOptions(), at: context.url)
		try Data("unreviewed new work\n".utf8).write(to: file)
		if action == .unstage { _ = try await run(["add", "file.txt"], in: context) }
		let indexBefore = try await run(["show", ":file.txt"], in: context)
		let headBefore = try await run(["rev-parse", "HEAD"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestApplyDiffHunk(
				.init(oldStartLine: 1, newStartLine: 1), action: action, for: change,
				expecting: displayed, options: GitDiffOptions(), at: context.url)
		}

		#expect(try String(contentsOf: file, encoding: .utf8) == "unreviewed new work\n")
		#expect(try await run(["show", ":file.txt"], in: context) == indexBefore)
		#expect(try await run(["rev-parse", "HEAD"], in: context) == headBefore)
	}

	@Test(arguments: [GitDiffLineAction.stage, .unstage])
	func staleLineActionsPreserveNewWorkingAndIndexContents(action: GitDiffLineAction) async throws {
		let context = try await makeContext()
		let file = context.url.appending(path: "file.txt")
		try Data("base\n".utf8).write(to: file)
		_ = try await run(["add", "file.txt"], in: context)
		_ = try await run(["commit", "-m", "base file"], in: context)
		try Data("reviewed\n".utf8).write(to: file)
		if action == .unstage { _ = try await run(["add", "file.txt"], in: context) }
		let source: GitDiffSource = action == .unstage ? .staged : .unstaged
		let change = try #require(
			try await context.repository.requestWorkingTreeChanges(at: context.url).first)
		let displayed = try await context.repository.requestDiff(
			for: change, source: source, options: GitDiffOptions(), at: context.url)
		try Data("unreviewed new work\n".utf8).write(to: file)
		if action == .unstage { _ = try await run(["add", "file.txt"], in: context) }
		let indexBefore = try await run(["show", ":file.txt"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestApplyDiffLine(
				.init(oldLineNumber: 1, newLineNumber: 1), action: action, for: change,
				expecting: displayed, options: GitDiffOptions(), at: context.url)
		}

		#expect(try String(contentsOf: file, encoding: .utf8) == "unreviewed new work\n")
		#expect(try await run(["show", ":file.txt"], in: context) == indexBefore)
	}

	@Test(arguments: ["ours", "theirs", "hunk"])
	func conflictResolutionPreservesAnEditMadeAfterValidation(selection: String) async throws {
		let context = try await makeContext()
		let conflict = try await makeConflict(in: context)
		let selected = try await context.repository.requestConflictContent(
			for: conflict, at: context.url)
		let file = context.url.appending(path: conflict.path)
		let index = try await run(["ls-files", "--stage", "-z"], in: context)
		let executable = context.url.appending(path: ".git/concurrent-git")
		let command =
			selection == "hunk" ? "rev-parse --absolute-git-dir" : "update-index -z --index-info"
		try """
		#!/bin/sh
		case " $* " in
		  *" \(command) "*) printf 'external save' > '\(file.path)' || exit 91 ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(configuration: GitProcessConfiguration(executableURL: executable)))

		let hunk = try #require(selected.hunks.first)
		let contents = try #require(selected.workingTree)
		await #expect(throws: GitRepositoryError.self) {
			if selection == "hunk" {
				try await repository.requestResolveConflictHunk(
					hunk, in: conflict, using: .incoming, expecting: contents, at: context.url)
			} else {
				try await repository.requestResolveConflict(
					conflict, using: selection == "ours" ? .ours : .theirs, expecting: selected,
					at: context.url)
			}
		}

		#expect(try String(contentsOf: file, encoding: .utf8) == "external save")
		#expect(try await run(["ls-files", "--stage", "-z"], in: context) == index)
		#expect(try await repository.requestOperationState(at: context.url).conflicts == [conflict])
	}

	@Test(arguments: ["removedFirst", "modifiedFirst", "identicalHunks", "outsideHunks"])
	func staleConflictResolutionPreservesTheEntireEditedFile(edit: String) async throws {
		let context = try await makeContext()
		let conflict = try await makeConflict(in: context)
		let first = "<<<<<<< HEAD\nours-first\n=======\ntheirs-first\n>>>>>>> incoming\n"
		let second =
			edit == "identicalHunks"
			? first : "<<<<<<< HEAD\nours-second\n=======\ntheirs-second\n>>>>>>> incoming\n"
		let expected = first + "middle\n" + second
		let file = context.url.appending(path: conflict.path)
		try Data(expected.utf8).write(to: file)
		let content = try await context.repository.requestConflictContent(
			for: conflict, at: context.url)
		let selected = try #require(content.hunks.first)
		let edited: String
		switch edit {
		case "removedFirst", "identicalHunks":
			edited = "ours-first\nmiddle\n" + second
		case "modifiedFirst":
			edited = expected.replacingOccurrences(of: "ours-first", with: "new work")
		default:
			edited = "new work outside conflicts\n" + expected
		}
		try Data(edited.utf8).write(to: file)
		let indexBefore = try await run(["ls-files", "--stage", "-z"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestResolveConflictHunk(
				selected, in: conflict, using: .incoming, expecting: expected, at: context.url)
		}

		#expect(try String(contentsOf: file, encoding: .utf8) == edited)
		#expect(try await run(["ls-files", "--stage", "-z"], in: context) == indexBefore)
	}

	@Test(arguments: [GitConflictHunkResolution.current, .incoming, .both])
	func currentConflictResolutionOnlyChangesTheSelectedHunk(resolution: GitConflictHunkResolution)
		async throws
	{
		let context = try await makeContext()
		let conflict = try await makeConflict(in: context)
		let first = "<<<<<<< HEAD\nours-first\n=======\ntheirs-first\n>>>>>>> incoming\n"
		let second = "<<<<<<< HEAD\nours-second\n=======\ntheirs-second\n>>>>>>> incoming\n"
		let expected = first + "middle\n" + second
		let file = context.url.appending(path: conflict.path)
		try Data(expected.utf8).write(to: file)
		let content = try await context.repository.requestConflictContent(
			for: conflict, at: context.url)
		let selected = try #require(content.hunks.last)
		let indexBefore = try await run(["ls-files", "--stage", "-z"], in: context)

		try await context.repository.requestResolveConflictHunk(
			selected, in: conflict, using: resolution, expecting: expected, at: context.url)

		let replacement: String
		switch resolution {
		case .current: replacement = "ours-second\n"
		case .incoming: replacement = "theirs-second\n"
		case .both: replacement = "ours-second\ntheirs-second\n"
		}
		#expect(try String(contentsOf: file, encoding: .utf8) == first + "middle\n" + replacement)
		#expect(try await run(["ls-files", "--stage", "-z"], in: context) == indexBefore)
	}

	@Test
	func automaticFetchCannotAuthorizeOverwritingAnUnseenRemoteCommit() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/main", at: context.url)
		let other = context.url.appending(path: ".git/other")
		_ = try await run(["clone", "--branch", "main", remote.path, other.path], in: context)
		_ = try await context.runner.requestRun(
			arguments: ["commit", "--allow-empty", "-m", "another user's work"], at: other)
		let remoteHead = try await context.runner.requestRun(
			arguments: ["rev-parse", "HEAD"], at: other)
		_ = try await context.runner.requestRun(arguments: ["push", "origin", "main"], at: other)
		_ = try await run(["commit", "--allow-empty", "-m", "independent local work"], in: context)
		let localHead = try await run(["rev-parse", "HEAD"], in: context)
		try await context.repository.requestFetchAll(at: context.url, allowsUserInteraction: false)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestForcePush(
				.upstream(), expecting: try await requestCurrentBranch(in: context),
				remotes: context.repository.requestRemotes(at: context.url), at: context.url)
		}

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: remote)
		#expect(actual.standardOutput == remoteHead.standardOutput)
		#expect(try await run(["rev-parse", "HEAD"], in: context) == localHead)
	}

	@Test(arguments: [false, true])
	func pullingADeletedUpstreamFailsWithoutChangingLocalHistory(prunes: Bool) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/release"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/release", at: context.url)
		_ = try await run(["config", "fetch.prune", prunes ? "true" : "false"], in: context)
		_ = try await context.runner.requestRun(
			arguments: ["update-ref", "-d", "refs/heads/release"], at: remote)
		let head = try await run(["rev-parse", "HEAD"], in: context)

		await #expect(throws: GitRepositoryError.self) {
			_ = try await context.repository.requestPreparePull(
				expecting: requestCurrentBranch(in: context), at: context.url)
		}

		#expect(try await run(["rev-parse", "HEAD"], in: context) == head)
		#expect(try await context.repository.requestOperationState(at: context.url).isIdle)
	}

	@Test
	func historyIncludesDetachedCommitsOutsideBranchesAndTags() async throws {
		let context = try await makeContext()
		let original = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["switch", "--detach", "HEAD"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "detached work"], in: context)
		let detached = try await run(["rev-parse", "HEAD"], in: context)

		let history = try await context.repository.requestCommitHistory(at: context.url)

		#expect(history.first?.hash == detached)
		#expect(history.first?.references.contains("HEAD") == true)
		#expect(Set(history.map(\.hash)) == [original, detached])
	}

	@Test
	func anUnbornHeadStillLoadsHistoryFromExistingReferences() async throws {
		let context = try await makeContext()
		let original = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["switch", "--orphan", "unborn"], in: context)

		let history = try await context.repository.requestCommitHistory(at: context.url)

		#expect(history.map(\.hash) == [original])
	}

	private func makeConflict(in context: Context) async throws -> GitConflict {
		let file = context.url.appending(path: "conflict.txt")
		try Data("base\n".utf8).write(to: file)
		_ = try await run(["add", "conflict.txt"], in: context)
		_ = try await run(["commit", "-m", "base file"], in: context)
		let original = try await run(["branch", "--show-current"], in: context)
		_ = try await run(["switch", "-c", "incoming"], in: context)
		try Data("incoming\n".utf8).write(to: file)
		_ = try await run(["commit", "-am", "incoming change"], in: context)
		_ = try await run(["switch", original], in: context)
		try Data("current\n".utf8).write(to: file)
		_ = try await run(["commit", "-am", "current change"], in: context)
		try await context.repository.requestMergeBranch(named: "incoming", at: context.url)
		return try #require(
			try await context.repository.requestOperationState(at: context.url).conflicts.first)
	}

	@Test(arguments: ["branch", "head", "upstream"])
	func forcePushRejectsAnOutdatedBranchSnapshot(change: String) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestCreateTrackingBranch(
			named: "tracked", tracking: "origin/main", at: context.url)
		let expected = try await requestCurrentBranch(in: context)
		switch change {
		case "branch": _ = try await run(["switch", "-c", "other"], in: context)
		case "head": _ = try await run(["commit", "--allow-empty", "-m", "changed HEAD"], in: context)
		default: _ = try await run(["branch", "--unset-upstream"], in: context)
		}

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestForcePush(
				.upstream(), expecting: expected,
				remotes: context.repository.requestRemotes(at: context.url), at: context.url)
		}

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: remote)
		#expect(actual.standardOutput.trimmingCharacters(in: .newlines) == expected.hash)
	}

	@Test
	func forcePushToAnAlternateRemoteUsesTheLocalBranchName() async throws {
		let context = try await makeContext()
		let source = try await makeRemote(in: context)
		let alternate = context.url.appending(path: ".git/alternate.git")
		_ = try await run(["init", "--bare", alternate.path], in: context)
		_ = try await run(["remote", "add", "alternate", alternate.path], in: context)
		let original = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["push", "-u", "origin", "HEAD:refs/heads/published"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "reviewed change"], in: context)
		let branch = try await requestCurrentBranch(in: context)
		let remotes = try await context.repository.requestRemotes(at: context.url)

		try await context.repository.requestForcePush(
			.upstream(remoteName: "alternate"), expecting: branch, remotes: remotes, at: context.url)

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/\(branch.name)"], at: alternate)
		let unaffected = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/published"], at: source)
		#expect(actual.standardOutput == branch.hash + "\n")
		#expect(unaffected.standardOutput == original + "\n")
		#expect(try await requestCurrentBranch(in: context).upstream == branch.upstream)
	}

	@Test(arguments: [false, true])
	func forcePushUsesTheReviewedRemoteTipEvenAfterAnotherFetch(customTracking: Bool) async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		if customTracking {
			_ = try await run(
				["config", "remote.origin.fetch", "+refs/heads/*:refs/custom/origin/*"], in: context)
		}
		_ = try await run(["push", "-u", "origin", "HEAD:refs/heads/main"], in: context)
		try await context.repository.requestFetch(remote: "origin", at: context.url)
		_ = try await run(["commit", "--allow-empty", "-m", "middle"], in: context)
		let middle = try await run(["rev-parse", "HEAD"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "reviewed"], in: context)
		let branch = try await requestCurrentBranch(in: context)
		let remotes = try await context.repository.requestRemotes(at: context.url)
		_ = try await run(["push", remote.path, "\(middle):refs/heads/main"], in: context)
		try await context.repository.requestFetch(remote: "origin", at: context.url)

		await #expect(throws: GitRepositoryError.self) {
			try await context.repository.requestForcePush(
				.upstream(), expecting: branch, remotes: remotes, at: context.url)
		}

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: remote)
		#expect(actual.standardOutput == middle + "\n")
		#expect(try await run(["rev-parse", "HEAD"], in: context) == branch.hash)
	}

	@Test
	func forcePushUsesTheConfiguredTrackingReferenceForTheSelectedBranch() async throws {
		let context = try await makeContext()
		let remote = try await makeRemote(in: context)
		_ = try await run(["push", "origin", "HEAD:refs/heads/main"], in: context)
		_ = try await run(
			["config", "remote.origin.fetch", "+refs/heads/*:refs/custom/origin/*"], in: context)
		try await context.repository.requestFetch(remote: "origin", at: context.url)
		_ = try await run(["switch", "-c", "tracked"], in: context)
		_ = try await run(["config", "branch.tracked.remote", "origin"], in: context)
		_ = try await run(["config", "branch.tracked.merge", "refs/heads/main"], in: context)
		_ = try await run(["commit", "--allow-empty", "-m", "reviewed work"], in: context)
		let expected = try await requestCurrentBranch(in: context)

		try await context.repository.requestForcePush(
			.upstream(), expecting: expected, remotes: context.repository.requestRemotes(at: context.url),
			at: context.url)

		let actual = try await context.runner.requestRun(
			arguments: ["rev-parse", "refs/heads/main"], at: remote)
		#expect(actual.standardOutput.trimmingCharacters(in: .newlines) == expected.hash)
	}

	private func requestCurrentBranch(in context: Context) async throws -> GitBranch {
		try #require(
			try await context.repository.requestBranches(at: context.url).first(where: \.isCurrent))
	}

	private func makeContext() async throws -> Context {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "PluminonReferenceMutations-\(UUID().uuidString)")
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

	private func makeRemote(in context: Context, name: String = "test-remote.git") async throws -> URL
	{
		let remote = context.url.appending(path: ".git").appending(path: name)
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
