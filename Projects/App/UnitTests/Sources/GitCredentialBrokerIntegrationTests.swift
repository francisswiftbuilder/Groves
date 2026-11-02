import Darwin
import Foundation
import Testing

@testable import CoreGitCredential
@testable import DataGit
@testable import Groves

@MainActor
struct GitCredentialBrokerIntegrationTests {
	@Test
	func theBundledHelperReadsCredentialsFromTheParentWithoutSharedKeychainAccess() async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let store = makeStore()
		let descriptor = GitCredentialDescriptor(
			kind: .https, host: "github.com", account: "broker-fixture")
		try store.save(secret: "exists-only-in-parent-memory", for: descriptor)
		let identifier = UUID().uuidString
		let broker = try GitCredentialBroker(
			helperURL: helperURL, operationID: identifier, helper: GitCredentialHelper(store: store))
		defer { broker.stop() }

		let result = try await Self.run(
			helperURL, arguments: ["credential", "get"],
			environment: [
				"GROVES_CREDENTIAL_SOCKET": broker.socketPath, "GROVES_OPERATION_IDENTIFIER": identifier,
			],
			input: "protocol=https\nhost=github.com\nusername=broker-fixture\n\n")

		#expect(result.status == EXIT_SUCCESS, "\(String(decoding: result.error, as: UTF8.self))")
		#expect(
			String(decoding: result.output, as: UTF8.self)
				== "password=exists-only-in-parent-memory\nusername=broker-fixture\n\n")
		let diagnostic = String(decoding: result.error, as: UTF8.self)
		#expect(!diagnostic.contains("Groves authentication helper failed"))
		#expect(!diagnostic.contains("exists-only-in-parent-memory"))
	}

	@Test(arguments: ["missing", "stopped", "wrong-operation"])
	func anUnavailableBrokerNeverFallsBackToTheHelperKeychain(reason: String) async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let identifier = UUID().uuidString
		let broker = try GitCredentialBroker(
			helperURL: helperURL, operationID: identifier, helper: GitCredentialHelper(store: makeStore())
		)
		defer { broker.stop() }
		if reason == "stopped" { broker.stop() }
		let environment: [String: String] =
			reason == "missing"
			? [:]
			: [
				"GROVES_CREDENTIAL_SOCKET": broker.socketPath,
				"GROVES_OPERATION_IDENTIFIER": reason == "wrong-operation" ? "stale" : identifier,
			]

		let result = try await Self.run(
			helperURL, arguments: ["credential", "get"], environment: environment,
			input: "protocol=https\nhost=github.com\nusername=broker-fixture\n\n")

		#expect(result.status == EXIT_FAILURE)
		#expect(String(decoding: result.output, as: UTF8.self) == "quit=true\n\n")
		#expect(String(decoding: result.error, as: UTF8.self).contains("credential-broker"))
	}

	@Test
	func aChildWithADifferentCodeSignatureCannotRequestCredentials() async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let store = makeStore()
		let descriptor = GitCredentialDescriptor(
			kind: .https, host: "github.com", account: "broker-fixture")
		try store.save(secret: "must-not-be-returned", for: descriptor)
		let broker = try GitCredentialBroker(
			helperURL: helperURL, operationID: UUID().uuidString,
			helper: GitCredentialHelper(store: store))
		defer { broker.stop() }

		let result = try await Self.run(
			URL(fileURLWithPath: "/usr/bin/nc"), arguments: ["-U", "-d", broker.socketPath])

		try #require(result.output.count > 4)
		let response = try JSONDecoder().decode(
			GitCredentialBrokerMessage.Response.self, from: result.output.dropFirst(4))
		guard case .failure(let diagnostic) = response else {
			Issue.record("An unrelated child process must not receive credentials")
			return
		}
		#expect(diagnostic.contains("untrusted-peer"))
		#expect(!String(decoding: result.output, as: UTF8.self).contains("must-not-be-returned"))
	}

	@Test(arguments: ["github.com", "GitHub.com", "github.com:443"])
	func theGitRunnerUsesTheBundledHelperWithParentOwnedCredentials(host: String) async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let store = makeStore()
		let descriptor = GitCredentialDescriptor(
			kind: .https, host: "github.com", account: "broker-fixture")
		try store.save(secret: "parent-runner-secret", for: descriptor)
		let directory = FileManager.default.temporaryDirectory.appending(
			path: "GrovesBrokerRunner-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let runtime = Bundle.main.bundleURL.appending(path: "Contents/Resources/Git")
		let defaultsName = "Groves.Broker.Selection.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: defaultsName))
		defer { defaults.removePersistentDomain(forName: defaultsName) }
		let selection = GitHubAccountSelection(defaults: defaults)
		selection.select(descriptor.account)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				executableURL: runtime.appending(path: "bin/git"), runtimeURL: runtime,
				askPassHelperURL: helperURL, globalConfigurationURL: directory.appending(path: "config")),
			credentialStore: store, credentialHelper: GitCredentialHelper(store: store),
			accountSelection: selection)

		let result = try await runner.requestRun(
			arguments: ["credential", "fill"], at: directory,
			standardInput: "protocol=https\nhost=\(host)\nusername=broker-fixture\n\n",
			isNetworkOperation: true)

		#expect(
			Set(result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)) == [
				"protocol=https", "host=\(host)", "username=broker-fixture",
				"password=parent-runner-secret",
			])
		#expect(!result.standardError.contains("parent-runner-secret"))
	}

	@Test
	func switchingAccountsDuringPreflightOnlyAffectsTheNextGitOperation() async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let store = makeStore()
		for account in ["alice", "zoe"] {
			try store.save(
				secret: "\(account)-token",
				for: GitCredentialDescriptor(kind: .https, host: "github.com", account: account))
		}
		let identifier = "Groves.Broker.Switch.\(UUID().uuidString)"
		let directory = FileManager.default.temporaryDirectory.appending(path: identifier)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let defaults = try #require(UserDefaults(suiteName: identifier))
		defer { defaults.removePersistentDomain(forName: identifier) }
		let selection = GitHubAccountSelection(defaults: defaults)
		selection.select("alice")
		let runtime = Bundle.main.bundleURL.appending(path: "Contents/Resources/Git")
		let executable = directory.appending(path: "gated-git")
		try """
		#!/bin/sh
		case " $* " in
		  *" config "*)
		    touch "$(dirname "$0")/started"
		    while [ ! -f "$(dirname "$0")/released" ]; do sleep 0.01; done
		    ;;
		esac
		exec '\(runtime.appending(path: "bin/git").path.replacingOccurrences(of: "'", with: "'\\''"))' "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				executableURL: executable, runtimeURL: runtime, askPassHelperURL: helperURL,
				globalConfigurationURL: directory.appending(path: "config")),
			credentialStore: store, credentialHelper: GitCredentialHelper(store: store),
			accountSelection: selection)
		let operation = Task {
			try await runner.requestRun(
				arguments: ["credential", "fill"], at: directory,
				standardInput: "protocol=https\nhost=github.com\n\n", isNetworkOperation: true)
		}
		defer {
			try? Data().write(to: directory.appending(path: "released"))
			operation.cancel()
		}
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while !FileManager.default.fileExists(atPath: directory.appending(path: "started").path) {
			try #require(ContinuousClock.now < deadline, "Git preflight did not start")
			try await Task.sleep(for: .milliseconds(10))
		}

		selection.select("zoe")
		try Data().write(to: directory.appending(path: "released"))
		let original = try await operation.value
		let next = try await runner.requestRun(
			arguments: ["credential", "fill"], at: directory,
			standardInput: "protocol=https\nhost=github.com\nusername=alice\n\n", isNetworkOperation: true
		)

		#expect(original.standardOutput.contains("password=alice-token"))
		#expect(!original.standardOutput.contains("zoe-token"))
		#expect(next.standardOutput.contains("username=zoe"))
		#expect(next.standardOutput.contains("password=zoe-token"))
		#expect(!next.standardOutput.contains("alice-token"))
	}

	@Test
	func gitStopsAfterABrokerFailureInsteadOfOpeningAnAskPassPrompt() async throws {
		let helperURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		let runtime = Bundle.main.bundleURL.appending(path: "Contents/Resources/Git")
		let escapedHelper = helperURL.path.replacingOccurrences(of: "'", with: "'\\''")

		let result = try await Self.run(
			runtime.appending(path: "bin/git"),
			arguments: [
				"-c", "credential.helper=", "-c", "credential.helper=!'\(escapedHelper)' credential",
				"credential", "fill",
			],
			environment: [
				"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0",
				"GIT_ASKPASS": helperURL.path,
				"GIT_EXEC_PATH": runtime.appending(path: "libexec/git-core").path,
			],
			input: "protocol=https\nhost=github.com\nusername=broker-fixture\n\n")

		#expect(result.status != EXIT_SUCCESS)
		#expect(result.output.isEmpty)
		let diagnostic = String(decoding: result.error, as: UTF8.self)
		#expect(diagnostic.contains("told us to quit"))
		#expect(diagnostic.contains("credential-broker"))
	}

	private func makeStore() -> GitCredentialStore {
		GitCredentialStore(
			service: "Groves.Broker.Tests.\(UUID().uuidString)",
			securityClient: GitAccountViewModelTests.SecurityClientStub(),
			accessGroupResolver: { throw GitCredentialStoreError.missingAccessGroup })
	}

	nonisolated private static func run(
		_ executable: URL, arguments: [String], environment: [String: String] = [:],
		input: String? = nil
	) async throws -> (status: Int32, output: Data, error: Data) {
		try await Task.detached {
			let process = Process()
			process.executableURL = executable
			process.arguments = arguments
			process.environment = ProcessInfo.processInfo.environment.filter {
				!$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("GROVES_")
			}.merging(environment) { _, new in new }
			let output = Pipe()
			let error = Pipe()
			let standardInput = input.map { _ in Pipe() }
			process.standardOutput = output
			process.standardError = error
			process.standardInput = standardInput ?? FileHandle.nullDevice
			try process.run()
			if let input, let standardInput {
				try standardInput.fileHandleForWriting.write(contentsOf: Data(input.utf8))
				try standardInput.fileHandleForWriting.close()
			}
			process.waitUntilExit()
			return (
				process.terminationStatus, output.fileHandleForReading.readDataToEndOfFile(),
				error.fileHandleForReading.readDataToEndOfFile()
			)
		}.value
	}
}
