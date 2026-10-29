import CoreGitCredential
import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitIsolatedConfigurationTests {
	@Test
	func testNetworkOperationsIgnoreGlobalAndURLSpecificAuthenticationSettings() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: ".git/app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		let settings = [
			"http.extraHeader": "Authorization: Basic external-account",
			"http.https://github.com/.extraHeader": "Authorization: Basic repository-account",
			"http.cookieFile": "/external/cookies",
			"http.https://github.com/.cookieFile": "/repository/cookies",
		]
		for (key, value) in settings {
			_ = try await runner.requestRun(
				arguments: ["config", "--local", key, value], at: repositoryURL)
		}

		for key in ["http.extraHeader", "http.cookieFile"] {
			let result = try await runner.requestRun(
				arguments: ["config", "--get-urlmatch", key, "https://github.com/owner/repo"],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 1],
				isNetworkOperation: true
			)
			#expect(result.standardOutput.trimmingCharacters(in: .newlines).isEmpty)
		}
		for (key, value) in settings {
			let result = try await runner.requestRun(
				arguments: ["config", "--local", "--get", key], at: repositoryURL)
			#expect(result.standardOutput.trimmingCharacters(in: .newlines) == value)
		}
	}

	@Test
	func testNetworkOperationsUsePrivateHomeForNetrcAndCurlConfiguration() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let configURL = repositoryURL.appending(path: ".git/app.config")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
			credentialStore: GitCredentialPersistingStub()
		)
		let result = try await runner.requestRun(
			arguments: [
				"-c", "alias.home=!printf '%s\\n' \"$HOME\" \"$CURL_HOME\" \"$XDG_CONFIG_HOME\"", "home",
			],
			at: repositoryURL,
			environment: ["HOME": "/external/home", "CURL_HOME": "/external/curl"],
			isNetworkOperation: true
		)
		let paths = result.standardOutput.split(separator: "\n").map(String.init)
		#expect(paths.count == 3)
		#expect(paths.first != "/external/home")
		#expect(paths.first == paths.dropFirst().first)
		#expect(paths.allSatisfy { $0.hasPrefix(configURL.deletingLastPathComponent().path) })
	}

	@Test
	func testExistingRemoteWithEmbeddedCredentialsIsRejectedBeforeFetch() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: ".git/app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		_ = try await runner.requestRun(
			arguments: [
				"config", "remote.origin.url", "https://external:secret@127.0.0.1:1/repo.git",
			], at: repositoryURL)
		let repository = LocalGitRepository(runner: runner)

		do {
			try await repository.requestFetch(remote: "origin", at: repositoryURL)
			Issue.record("Expected an embedded credential rejection")
		} catch GitRepositoryError.invalidRemoteURL {}
	}

	@Test
	func testCloneRejectsCredentialsIntroducedByURLRewriting() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: ".git/app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		_ = try await runner.requestRun(
			arguments: [
				"config", "url.https://external:secret@127.0.0.1:1/.insteadOf", "https://example.com/",
			], at: repositoryURL)
		let repository = LocalGitRepository(runner: runner)

		do {
			_ = try await repository.requestCloneRepository(
				from: "https://example.com/repo.git", into: repositoryURL)
			Issue.record("Expected rewritten credentials to be rejected before cloning")
		} catch GitRepositoryError.invalidRemoteURL {}
		#expect(!(FileManager.default.fileExists(atPath: repositoryURL.appending(path: "repo").path)))
	}

	@Test
	func testConfiguredClientCertificateStopsBeforeTheNetworkCommandStarts() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: ".git/app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		let markerURL = repositoryURL.appending(path: "network-started")
		_ = try await runner.requestRun(
			arguments: ["config", "http.https://github.com/.sslCert", "/external/client.pem"],
			at: repositoryURL)

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.mark=!touch '\(markerURL.path)'", "mark"],
				at: repositoryURL, isNetworkOperation: true)
			Issue.record("Expected client certificate isolation guidance")
		} catch GitRepositoryError.authentication(let message) {
			#expect(message.contains("TLS client certificates"))
		}
		#expect(!(FileManager.default.fileExists(atPath: markerURL.path)))
	}

	@Test
	func testCredentialsInAuthenticationURLContextAreRejectedWithoutBeingReported() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: ".git/app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		_ = try await runner.requestRun(
			arguments: [
				"config", "http.https://external:private-token@github.com/.extraHeader", "X-Example: value",
			], at: repositoryURL)

		do {
			_ = try await runner.requestRun(
				arguments: [
					"config", "--get-urlmatch", "http.extraHeader", "https://github.com/owner/repo",
				],
				at: repositoryURL, isNetworkOperation: true)
			Issue.record("Expected authentication context rejection")
		} catch GitRepositoryError.authentication(let message) {
			#expect(!(message.contains("private-token")))
			#expect(!(message.contains("external")))
		}
	}

	@Test
	func testIsolatedCloneCommitAndPushUseSavedIdentity() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let configURL = directoryURL.appending(path: "app.config")
		try GitIdentityConfiguration(name: "Groves Author", email: "groves@example.com").save(
			to: configURL)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
			credentialStore: GitCredentialPersistingStub()
		)
		let remoteURL = directoryURL.appending(path: "remote.git")
		_ = try await runner.requestRun(
			arguments: ["init", "--bare", "--initial-branch=main", remoteURL.path], at: directoryURL)
		let cloneDirectoryURL = directoryURL.appending(path: "checkouts")
		try FileManager.default.createDirectory(
			at: cloneDirectoryURL, withIntermediateDirectories: true)
		let repository = LocalGitRepository(runner: runner)
		let repositoryURL = try await repository.requestCloneRepository(
			from: remoteURL.path, into: cloneDirectoryURL)
		try "First change\n".write(
			to: repositoryURL.appending(path: "README.md"), atomically: true, encoding: .utf8)
		try await repository.requestStage(path: "README.md", at: repositoryURL)
		try await repository.requestCommit(
			subject: "First commit", body: "Commit description", amend: false, at: repositoryURL)
		try await repository.requestPush(
			.setUpstream(remoteName: "origin", branchName: "main"), at: repositoryURL)

		let author = try await runner.requestRun(
			arguments: ["log", "-1", "--format=%an%n%ae%n%B"], at: remoteURL)
		#expect(
			author.standardOutput.trimmingCharacters(in: .newlines)
				== "Groves Author\ngroves@example.com\nFirst commit\n\nCommit description")
		let branch = try await repository.requestBranches(at: repositoryURL).first(where: \.isCurrent)
		#expect(branch?.upstream == "origin/main")
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		#expect(changes.isEmpty)
	}

	@Test
	func testMissingIdentityCanBeConfiguredAndCommitRetried() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let configURL = repositoryURL.appending(path: ".git/app.config")
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
				credentialStore: GitCredentialPersistingStub()
			)
		)
		try "Change\n".write(
			to: repositoryURL.appending(path: "README.md"), atomically: true, encoding: .utf8)
		try await repository.requestStage(path: "README.md", at: repositoryURL)

		do {
			try await repository.requestCommit(
				subject: "First commit", body: "", amend: false, at: repositoryURL)
			Issue.record("Expected missing identity guidance")
		} catch GitRepositoryError.commandFailed(let message) {
			#expect(message.contains("Settings → Accounts"))
		}
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		#expect(changes.filter(\.isStaged).map(\.path) == ["README.md"])
		try GitIdentityConfiguration(name: "Groves Author", email: "groves@example.com").save(
			to: configURL)
		try await repository.requestCommit(
			subject: "First commit", body: "", amend: false, at: repositoryURL)
		let commits = try await repository.requestCommitHistory(at: repositoryURL)
		#expect(commits.map(\.subject) == ["First commit"])
	}

	@Test
	func testHelperTerminationIsNotReportedAsInvalidCredentials() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: "app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		do {
			_ = try await runner.requestRun(
				arguments: [
					"-c",
					"alias.fail=!printf '%s\\n' 'error: GrovesAskPass credential get died of signal 9' 'fatal: could not read Username: terminal prompts disabled' >&2; exit 1",
					"fail",
				],
				at: repositoryURL
			)
			Issue.record("Expected helper execution failure")
		} catch GitRepositoryError.commandFailed(let message) {
			#expect(message.contains("provisioning profile"))
			#expect(message.contains("died of signal 9"))
			#expect(!(message.contains("Check repository permissions")))
		}
	}

	@Test
	func testMissingRuntimeDoesNotFallBackToSystemGit() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				executableURL: repositoryURL.appending(path: "missing-git")),
			credentialStore: GitCredentialPersistingStub()
		)
		do {
			_ = try await runner.requestRun(arguments: ["status"], at: repositoryURL)
			Issue.record("Expected missing runtime error")
		} catch GitRepositoryError.commandFailed(let message) {
			#expect(message.contains("runtime is missing"))
		}
	}

	@Test
	func testRuntimeOverridesInheritedHelperAndExecutablePaths() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				runtimeURL: repositoryURL,
				globalConfigurationURL: repositoryURL.appending(path: "app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		let result = try await runner.requestRun(
			arguments: [
				"-c", "alias.runtime=!printf '%s\\n' \"$GIT_EXEC_PATH\" \"$GIT_TEMPLATE_DIR\"", "runtime",
			],
			at: repositoryURL,
			environment: ["GIT_EXEC_PATH": "/external/git", "GIT_TEMPLATE_DIR": "/external/templates"]
		)
		#expect(
			result.standardOutput == repositoryURL.appending(path: "libexec/git-core").path + "\n"
				+ repositoryURL.appending(path: "share/git-core/templates").path + "\n")
	}

	@Test
	func testAuthenticationFailurePreservesDetailsWithoutCredentials() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: "app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		do {
			_ = try await runner.requestRun(
				arguments: [
					"-c",
					"alias.fail=!printf '%s\\n' 'Authentication failed: organization approval required https://user:secret@example.com/repo ghp_fakeSecret authorization: Bearer fakeBearer password=fakePassword' >&2; exit 1",
					"fail",
				],
				at: repositoryURL
			)
			Issue.record("Expected authentication failure")
		} catch GitRepositoryError.authentication(let message) {
			#expect(message.contains("organization approval required"))
			#expect(message.contains("https://***@example.com/repo"))
			for secret in ["user:secret", "ghp_fakeSecret", "fakeBearer", "fakePassword"] {
				#expect(!(message.contains(secret)))
			}
		}
	}

	@Test
	func testIsolatedOperationsNeverOpenAnInteractiveEditor() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: "app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		let result = try await runner.requestRun(
			arguments: [
				"-c",
				"alias.editors=!printf '%s\\n' \"$GIT_EDITOR\" \"$GIT_SEQUENCE_EDITOR\" \"$GIT_MERGE_AUTOEDIT\"",
				"editors",
			],
			at: repositoryURL,
			environment: ["GIT_EDITOR": "external-editor"]
		)
		#expect(result.standardOutput == "/usr/bin/true\n/usr/bin/true\nno\n")
	}

	@Test
	func testIdentityQuotesRoundTripThroughGit() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let configURL = repositoryURL.appending(path: "app.config")
		let name = "User \"Quoted\" \\ Example"
		try GitIdentityConfiguration(name: name, email: "test@example.com").save(to: configURL)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
			credentialStore: GitCredentialPersistingStub()
		)
		let result = try await runner.requestRun(
			arguments: ["config", "--global", "user.name"], at: repositoryURL)
		#expect(result.standardOutput.trimmingCharacters(in: .newlines) == name)
	}

	@Test
	func testAppConfigurationOverridesInheritedGlobalConfigAndRuntimeInjection() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let configURL = repositoryURL.appending(path: "app.config")
		try GitIdentityConfiguration(name: "Groves Author", email: "groves@example.com").save(
			to: configURL)
		let foreignConfigURL = repositoryURL.appending(path: "foreign.config")
		try "[user]\nname = External Author\n".write(
			to: foreignConfigURL, atomically: true, encoding: .utf8)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
			credentialStore: GitCredentialPersistingStub()
		)
		let result = try await runner.requestRun(
			arguments: ["config", "--global", "user.name"],
			at: repositoryURL,
			environment: [
				"GIT_CONFIG_GLOBAL": foreignConfigURL.path,
				"GIT_CONFIG_COUNT": "1",
				"GIT_CONFIG_KEY_0": "user.name",
				"GIT_CONFIG_VALUE_0": "Injected Author",
			]
		)
		#expect(
			result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "Groves Author")
	}

	@Test
	func testLocalRepositoryIdentityStillTakesPrecedence() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let configURL = repositoryURL.appending(path: "app.config")
		try GitIdentityConfiguration(name: "App Author", email: "app@example.com").save(to: configURL)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(globalConfigurationURL: configURL),
			credentialStore: GitCredentialPersistingStub()
		)
		_ = try await runner.requestRun(
			arguments: ["config", "--local", "user.name", "Local Author"], at: repositoryURL)
		let result = try await runner.requestRun(arguments: ["config", "user.name"], at: repositoryURL)
		#expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "Local Author")
	}

	@Test
	func testExternalCredentialHelperIsNotExecuted() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let markerURL = repositoryURL.appending(path: "external-helper-ran")
		let helperURL = repositoryURL.appending(path: "app-helper")
		try "#!/bin/sh\nprintf 'username=groves\\npassword=test-secret\\n\\n'\n".write(
			to: helperURL, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				askPassHelperURL: helperURL,
				globalConfigurationURL: repositoryURL.appending(path: "app.config")
			),
			credentialStore: GitCredentialPersistingStub()
		)
		_ = try await runner.requestRun(
			arguments: ["config", "--local", "credential.helper", "!touch '\(markerURL.path)'"],
			at: repositoryURL
		)
		let result = try await runner.requestRun(
			arguments: ["credential", "fill"],
			at: repositoryURL,
			standardInput: "protocol=https\nhost=github.com\n\n",
			isNetworkOperation: true
		)
		#expect(result.standardOutput.contains("username=groves"))
		#expect(!(FileManager.default.fileExists(atPath: markerURL.path)))
	}

	@Test
	func testSSHStopsWithHTTPSMigrationGuidance() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				globalConfigurationURL: repositoryURL.appending(path: "app.config")),
			credentialStore: GitCredentialPersistingStub()
		)
		do {
			_ = try await runner.requestRun(
				arguments: ["status"], at: repositoryURL, isNetworkOperation: true,
				requiresSSHTrustScope: true)
			Issue.record("Expected HTTPS guidance")
		} catch GitRepositoryError.authentication(let message) {
			#expect(message.contains("HTTPS"))
		}
	}
}
