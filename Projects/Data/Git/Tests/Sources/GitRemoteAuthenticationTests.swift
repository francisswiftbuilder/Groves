import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitRemoteAuthenticationTests {
	@Test(arguments: [
		"git@github.com:",
		"ssh://git@github.com/",
		"ssh://git@github.com:22/",
		"git+ssh://git@github.com/",
		"git+ssh://git@github.com:22/",
		"ssh://git@ssh.github.com:443/",
	])
	func gitHubSSHAddressesUseHTTPSWithoutEditingTheRemote(prefix: String) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = makeRunner(at: url)
		let original = prefix + "owner/repository.git"
		_ = try await runner.requestRun(arguments: ["remote", "add", "origin", original], at: url)
		_ = try await runner.requestRun(
			arguments: ["remote", "set-url", "--push", "origin", prefix + "owner/push.git"], at: url)
		let configuration = try Data(contentsOf: url.appending(path: ".git/config"))

		let fetch = try await runner.requestRun(arguments: ["remote", "get-url", "origin"], at: url)
		let push = try await runner.requestRun(
			arguments: ["remote", "get-url", "--push", "origin"], at: url)
		let clone = try await runner.requestRun(
			arguments: ["ls-remote", "--get-url", original], at: url)

		#expect(fetch.standardOutput == "https://github.com/owner/repository.git\n")
		#expect(push.standardOutput == "https://github.com/owner/push.git\n")
		#expect(clone.standardOutput == fetch.standardOutput)
		#expect(try Data(contentsOf: url.appending(path: ".git/config")) == configuration)
		let stored = try await runner.requestRun(
			arguments: ["config", "--local", "remote.origin.url"], at: url)
		#expect(stored.standardOutput == original + "\n")
	}

	@Test(arguments: [
		"git@github.com.evil.example:owner/repository.git",
		"ssh://git@github.com.evil.example/owner/repository.git",
		"ssh://git@github.com@evil.example/owner/repository.git",
		"git@gitlab.com:owner/repository.git",
		"ssh://git@github.com:2222/owner/repository.git",
		"https://github.com/owner/repository.git",
	])
	func otherAddressesAreNotRewritten(remote: String) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }

		let result = try await makeRunner(at: url).requestRun(
			arguments: ["ls-remote", "--get-url", remote], at: url)

		#expect(result.standardOutput == remote + "\n")
	}

	@Test
	func nonisolatedGitKeepsTheOriginalSSHTransport() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let remote = "git@github.com:owner/repository.git"
		let runner = GitProcessRunner(credentialStore: GitCredentialPersistingStub())

		let result = try await runner.requestRun(
			arguments: ["ls-remote", "--get-url", remote], at: url)

		#expect(result.standardOutput == remote + "\n")
	}

	@Test(arguments: [false, true])
	func gitHubSSHRemotesPassFetchPreflight(fetchAll: Bool) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let marker = url.appending(path: ".git/fetch-started")
		let executable = url.appending(path: ".git/test-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" fetch "*) touch '\(marker.path)'; exit 0 ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let store = GitCredentialPersistingStub()
		let runner = makeRunner(at: url, executable: executable, store: store)
		_ = try await runner.requestRun(
			arguments: ["remote", "add", "origin", "git@github.com:owner/repository.git"], at: url)
		let repository = LocalGitRepository(runner: runner)

		if fetchAll {
			try await repository.requestFetchAll(at: url)
		} else {
			try await repository.requestFetch(remote: "origin", at: url)
		}

		#expect(FileManager.default.fileExists(atPath: marker.path))
		#expect(store.commitCount == 1)
	}

	@Test
	func aMoreSpecificRewriteWithCredentialsStillFailsBeforeFetching() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = makeRunner(at: url)
		_ = try await runner.requestRun(
			arguments: ["remote", "add", "origin", "git@github.com:owner/repository.git"], at: url)
		_ = try await runner.requestRun(
			arguments: [
				"config", "url.https://external:private-token@github.com/.insteadOf",
				"git@github.com:owner/",
			], at: url)
		let repository = LocalGitRepository(runner: runner)

		do {
			try await repository.requestFetch(remote: "origin", at: url)
			Issue.record("Expected credentials in the rewritten URL to be rejected")
		} catch GitRepositoryError.invalidRemoteURL {}
	}

	@Test(arguments: ["keychain", "repository", "sso", "forbidden", "certificate"])
	func connectionFailuresExplainTheirCauseAndRedactSecrets(kind: String) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let input: String
		let expected: String
		switch kind {
		case "keychain":
			input = "Groves authentication helper failed (stage=copy-secret status=-25293)."
			expected = "Keychain"
		case "repository":
			input = "remote: Repository not found."
			expected = "Contents: Read"
		case "sso":
			input = "remote: The organization has enabled SAML SSO."
			expected = "single sign-on"
		case "forbidden":
			input = "fatal: The requested URL returned error: 403"
			expected = "organization approval"
		default:
			input = "fatal: SSL certificate problem: unable to get local issuer certificate"
			expected = "TLS certificate"
		}
		let diagnostic = input + " https://user:secret@github.com/owner/repo ghp_fakeSecret"
		let failure = url.appending(path: ".git/failure.txt")
		try diagnostic.write(to: failure, atomically: true, encoding: .utf8)
		let executable = url.appending(path: ".git/test-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" config "*) exec /usr/bin/git "$@" ;;
		esac
		cat '\(failure.path)' >&2
		exit 128
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let runner = makeRunner(at: url, executable: executable)

		do {
			_ = try await runner.requestRun(arguments: ["status"], at: url, isNetworkOperation: true)
			Issue.record("Expected a connection failure")
		} catch let error as GitRepositoryError {
			switch error {
			case .authentication:
				#expect(kind != "certificate")
			case .network:
				#expect(kind == "certificate")
			default:
				Issue.record("Incorrect error category: \(error)")
			}
			#expect(error.localizedDescription.contains(expected))
			#expect(error.localizedDescription.contains(input))
			#expect(!error.localizedDescription.contains("user:secret"))
			#expect(!error.localizedDescription.contains("ghp_fakeSecret"))
		}
	}

	private func makeRunner(
		at url: URL, executable: URL = URL(fileURLWithPath: "/usr/bin/git"),
		store: GitCredentialPersistingStub = GitCredentialPersistingStub()
	) -> GitProcessRunner {
		GitProcessRunner(
			configuration: GitProcessConfiguration(
				executableURL: executable, globalConfigurationURL: url.appending(path: ".git/app.config")),
			credentialStore: store)
	}
}
