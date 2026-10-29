import CoreGitCredential
import DomainGitInterface
import Foundation

actor GitProcessRunner {
	private let configuration: GitProcessConfiguration
	private let credentialStore: any GitCredentialPersisting
	private let decisionStore = GitCredentialSaveDecisionStore()

	init(
		configuration: GitProcessConfiguration = GitProcessConfiguration(),
		credentialStore: any GitCredentialPersisting = GitCredentialStore()
	) {
		self.configuration = configuration
		self.credentialStore = credentialStore
	}

	func requestRun(
		arguments: [String],
		at repositoryURL: URL,
		standardInput: String? = nil,
		environment: [String: String] = [:],
		acceptedTerminationStatuses: Set<Int32> = [0],
		isNetworkOperation: Bool = false,
		requiresSSHTrustScope: Bool = false
	) async throws -> GitCommandResult {
		try Task.checkCancellation()
		guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
			throw GitRepositoryError.commandFailed(
				"Groves Git runtime is missing. Reinstall Groves or rebuild its bundled Git runtime.")
		}
		if configuration.globalConfigurationURL != nil, requiresSSHTrustScope {
			throw GitRepositoryError.authentication(
				"Groves uses separate HTTPS credentials. Change this remote to its HTTPS URL, then connect your account in Settings."
			)
		}
		let operationID = UUID().uuidString
		var didSucceed = false
		defer {
			if isNetworkOperation, !didSucceed {
				try? credentialStore.discardPending(operationID: operationID)
				decisionStore.discard(operationID: operationID)
			}
		}

		var trustScope: GitSSHTrustScope?
		if isNetworkOperation && requiresSSHTrustScope {
			trustScope = try makeTrustScope()
		}
		defer { trustScope?.remove() }

		let authenticationArguments: [String]
		if isNetworkOperation, let homeURL = configuration.isolatedHomeDirectoryURL {
			try FileManager.default.createDirectory(
				at: homeURL,
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)
			authenticationArguments = try await requestAuthenticationArguments(
				at: repositoryURL, environment: environment, operationID: operationID)
		} else {
			authenticationArguments = []
		}
		let result = try await requestCommand(
			arguments: arguments,
			at: repositoryURL,
			standardInput: standardInput,
			environment: environment,
			acceptedTerminationStatuses: acceptedTerminationStatuses,
			isNetworkOperation: isNetworkOperation,
			operationID: operationID,
			trustScope: trustScope,
			authenticationArguments: authenticationArguments
		)
		if isNetworkOperation {
			commitPendingCredentials(operationID: operationID)
			decisionStore.discard(operationID: operationID)
		}
		didSucceed = true
		return result
	}

	private func requestCommand(
		arguments: [String],
		at repositoryURL: URL,
		standardInput: String? = nil,
		environment: [String: String] = [:],
		acceptedTerminationStatuses: Set<Int32> = [0],
		isNetworkOperation: Bool = false,
		operationID: String,
		trustScope: GitSSHTrustScope? = nil,
		authenticationArguments: [String] = []
	) async throws -> GitCommandResult {
		let standardOutputPipe = Pipe()
		let standardErrorPipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments =
			[
				"-c",
				"export GROVES_PARENT_PROCESS_IDENTIFIER=$$; exec /usr/bin/env \"$@\"",
				"GrovesGit",
			]
			+ gitArguments(
				arguments,
				repositoryURL: repositoryURL,
				isNetworkOperation: isNetworkOperation,
				authenticationArguments: authenticationArguments
			)
		process.environment = processEnvironment(
			merging: environment,
			operationID: operationID,
			isNetworkOperation: isNetworkOperation,
			trustScope: trustScope
		)
		process.standardOutput = standardOutputPipe
		process.standardError = standardErrorPipe
		let standardInputPipe = standardInput.map { _ in Pipe() }
		process.standardInput = standardInputPipe ?? FileHandle.nullDevice

		let standardOutputCollector = GitProcessOutputCollector(
			pipe: standardOutputPipe,
			label: "stdout"
		)
		let standardErrorCollector = GitProcessOutputCollector(
			pipe: standardErrorPipe,
			label: "stderr"
		)

		let terminationStatus = try await requestTerminationStatus(
			for: process,
			standardInput: standardInput,
			standardInputPipe: standardInputPipe,
			timeout: isNetworkOperation ? configuration.networkPolicy.operationTimeout : nil
		)
		let standardOutputData = await standardOutputCollector.data()
		let standardError = String(decoding: await standardErrorCollector.data(), as: UTF8.self)
		let standardOutput = String(decoding: standardOutputData, as: UTF8.self)
		try Task.checkCancellation()

		guard acceptedTerminationStatuses.contains(terminationStatus) else {
			if standardError.contains("GROVES_ASKPASS_CANCELLED") {
				throw CancellationError()
			}
			throw repositoryError(for: standardError)
		}
		return GitCommandResult(
			standardOutputData: standardOutputData,
			standardOutput: standardOutput,
			standardError: standardError
		)
	}

	private func requestAuthenticationArguments(
		at repositoryURL: URL,
		environment: [String: String],
		operationID: String
	) async throws -> [String] {
		let result = try await requestCommand(
			arguments: ["config", "--null", "--name-only", "--get-regexp", "^(http|credential)\\."],
			at: repositoryURL,
			environment: environment,
			acceptedTerminationStatuses: [0, 1],
			isNetworkOperation: true,
			operationID: operationID
		)
		let overrides = [
			"http.extraheader": "",
			"http.cookiefile": "",
			"http.savecookies": "false",
			"http.emptyauth": "false",
			"http.proactiveauth": "basic",
			"http.delegation": "none",
			"credential.helper": "",
			"credential.username": "",
			"credential.usehttppath": "false",
		]
		let keys = Set(result.standardOutput.split(separator: "\0").map(String.init))
		var arguments: [String] = []
		for key in keys.sorted() {
			let components = key.split(separator: ".")
			guard let section = components.first, let name = components.last else { continue }
			let baseKey = "\(section).\(name)".lowercased()
			if let firstDot = key.firstIndex(of: "."), let lastDot = key.lastIndex(of: "."),
				firstDot != lastDot
			{
				let context = String(key[key.index(after: firstDot)..<lastDot])
				guard !GitRemoteURLValidator.containsEmbeddedCredential(context) else {
					throw GitRepositoryError.authentication(
						"Repository authentication settings contain embedded credentials. Use your Groves account with an HTTPS remote URL."
					)
				}
			}
			if baseKey == "http.sslcert" || baseKey == "http.sslkey" {
				throw GitRepositoryError.authentication(
					"Repository-configured TLS client certificates cannot be used with Groves account isolation. Use an HTTPS remote with your Groves account."
				)
			}
			if let value = overrides[baseKey] {
				arguments += ["-c", "\(key)=\(value)"]
			}
		}
		for (key, value) in overrides.sorted(by: { $0.key < $1.key }) {
			arguments += ["-c", "\(key)=\(value)"]
		}
		return arguments
	}

	private func makeTrustScope() throws -> GitSSHTrustScope {
		do {
			return try GitSSHTrustScope(userKnownHostsURL: configuration.userKnownHostsURL)
		} catch {
			throw GitRepositoryError.hostVerification("")
		}
	}

	private func commitPendingCredentials(operationID: String) {
		do {
			try credentialStore.commitPending(operationID: operationID)
		} catch {
			let commitDiagnostic = credentialDiagnostic(for: error, stage: "commit")
			let discardDiagnostic: String?
			do {
				try credentialStore.discardPending(operationID: operationID)
				discardDiagnostic = nil
			} catch {
				discardDiagnostic = credentialDiagnostic(for: error, stage: "discard")
			}
			let diagnostic = [commitDiagnostic, discardDiagnostic]
				.compactMap { $0 }
				.joined(separator: "; ")
			configuration.noticeHandler?(.credentialPersistenceFailed(diagnostic: diagnostic))
		}
	}

	private func credentialDiagnostic(for error: any Error, stage: String) -> String {
		if let error = error as? GitCredentialStoreError {
			return "\(stage): \(error.diagnosticDescription)"
		}
		return "\(stage): error-type=\(String(reflecting: type(of: error)))"
	}

	private func processEnvironment(
		merging environment: [String: String],
		operationID: String,
		isNetworkOperation: Bool,
		trustScope: GitSSHTrustScope?
	) -> [String: String] {
		var result = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
		if let configurationURL = configuration.globalConfigurationURL {
			result = result.filter { key, _ in
				!key.hasPrefix("GIT_") && !key.hasPrefix("GROVES_") && !key.hasPrefix("SSH_")
			}
			result["GIT_CONFIG_GLOBAL"] = configurationURL.path
			result["GIT_CONFIG_NOSYSTEM"] = "1"
			result["GIT_CONFIG_SYSTEM"] = "/dev/null"
			result["GIT_ALLOW_PROTOCOL"] = "https:file"
			result["GIT_TERMINAL_PROMPT"] = "0"
			result["GIT_EDITOR"] = "/usr/bin/true"
			result["GIT_SEQUENCE_EDITOR"] = "/usr/bin/true"
			result["GIT_MERGE_AUTOEDIT"] = "no"
			result["LC_ALL"] = "C"
		}
		if let runtimeURL = configuration.runtimeURL {
			result["GIT_EXEC_PATH"] = runtimeURL.appending(path: "libexec/git-core").path
			result["GIT_TEMPLATE_DIR"] = runtimeURL.appending(path: "share/git-core/templates").path
			result["PATH"] = runtimeURL.appending(path: "bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
		}
		if isNetworkOperation {
			if let homeURL = configuration.isolatedHomeDirectoryURL {
				result["HOME"] = homeURL.path
				result["CURL_HOME"] = homeURL.path
				result["XDG_CONFIG_HOME"] = homeURL.appending(path: ".config").path
			}
			let policy = configuration.networkPolicy
			result["GIT_HTTP_LOW_SPEED_LIMIT"] = String(policy.lowSpeedLimit)
			result["GIT_HTTP_LOW_SPEED_TIME"] = String(Int(policy.lowSpeedTime))
			result["GIT_TERMINAL_PROMPT"] = "0"
			if let helperURL = configuration.askPassHelperURL {
				result["GIT_ASKPASS"] = helperURL.path
				result["SSH_ASKPASS"] = helperURL.path
				result["SSH_ASKPASS_REQUIRE"] = "force"
				result["GROVES_OPERATION_IDENTIFIER"] = operationID
			}
		}
		if let trustScope {
			let policy = configuration.networkPolicy
			result["GIT_SSH_COMMAND"] =
				([
					"ssh",
					"-o ConnectTimeout=\(Int(policy.sshConnectTimeout))",
					"-o ServerAliveInterval=\(Int(policy.sshServerAliveInterval))",
					"-o ServerAliveCountMax=\(policy.sshServerAliveCountMax)",
				] + trustScope.sshOptions).joined(separator: " ")
		}
		return result
	}

	private func gitArguments(
		_ arguments: [String],
		repositoryURL: URL,
		isNetworkOperation: Bool,
		authenticationArguments: [String]
	) -> [String] {
		var result = [configuration.executableURL.path]
		if configuration.globalConfigurationURL != nil {
			result += ["-c", "user.useConfigOnly=true"]
			if isNetworkOperation, configuration.askPassHelperURL == nil {
				result += ["-c", "credential.helper=", "-c", "core.askPass="]
			}
		}
		result += authenticationArguments
		if isNetworkOperation, let helperURL = configuration.askPassHelperURL {
			let escapedPath = helperURL.path.replacingOccurrences(of: "'", with: "'\\''")
			result += [
				"-c", "credential.helper=", "-c", "credential.helper=!'\(escapedPath)' credential",
			]
		}
		result += ["-C", repositoryURL.path]
		result += arguments
		return result
	}

	private func requestTerminationStatus(
		for process: Process,
		standardInput: String?,
		standardInputPipe: Pipe?,
		timeout: TimeInterval?
	) async throws -> Int32 {
		guard let timeout else {
			return try await waitForTermination(
				of: process,
				standardInput: standardInput,
				standardInputPipe: standardInputPipe
			)
		}

		return try await withThrowingTaskGroup(of: Int32.self) { group in
			group.addTask {
				try await self.waitForTermination(
					of: process,
					standardInput: standardInput,
					standardInputPipe: standardInputPipe
				)
			}
			group.addTask {
				try await Task.sleep(for: .seconds(timeout))
				throw GitRepositoryError.timeout
			}
			guard let status = try await group.next() else {
				throw GitRepositoryError.commandFailed("")
			}
			group.cancelAll()
			return status
		}
	}

	private func waitForTermination(
		of process: Process,
		standardInput: String?,
		standardInputPipe: Pipe?
	) async throws -> Int32 {
		let lifecycle = GitProcessLifecycle(
			process: process,
			gracePeriod: configuration.terminationGracePeriod
		)
		try Task.checkCancellation()
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				let didStart = lifecycle.start(
					onTermination: { continuation.resume(returning: $0) },
					onFailure: { error in
						try? standardInputPipe?.fileHandleForWriting.close()
						continuation.resume(throwing: error)
					}
				)
				guard didStart, let standardInput, let standardInputPipe else { return }
				Self.write(standardInput, to: standardInputPipe)
			}
		} onCancel: {
			lifecycle.cancel()
		}
	}

	nonisolated private static func write(_ standardInput: String, to pipe: Pipe) {
		DispatchQueue.global(qos: .userInitiated).async {
			let handle = pipe.fileHandleForWriting
			try? handle.write(contentsOf: Data(standardInput.utf8))
			try? handle.close()
		}
	}

	private func repositoryError(for standardError: String) -> GitRepositoryError {
		let message = redacted(standardError).trimmingCharacters(in: .whitespacesAndNewlines)
		let lowercasedMessage = message.lowercased()
		if configuration.globalConfigurationURL != nil {
			if lowercasedMessage.contains("identity unknown")
				|| lowercasedMessage.contains("auto-detection is disabled")
				|| lowercasedMessage.contains("unable to auto-detect email")
			{
				return .commandFailed(
					"Set your commit name and email in Groves Settings → Accounts, then retry.")
			}
			if lowercasedMessage.contains("transport")
				&& lowercasedMessage.contains("not allowed")
			{
				return .authentication(
					"This remote transport is not available in Groves. Use an HTTPS remote URL and connect your account in Settings."
				)
			}
		}
		if lowercasedMessage.contains("remote host identification has changed")
			|| lowercasedMessage.contains("host key verification failed")
			|| lowercasedMessage.contains("no matching host key")
		{
			return .hostVerification(message)
		}
		if lowercasedMessage.contains("operation too slow")
			|| lowercasedMessage.contains("operation timed out")
			|| lowercasedMessage.contains("timeout after")
		{
			return .timeout
		}
		if lowercasedMessage.contains("grovesaskpass")
			&& lowercasedMessage.contains("died of signal")
		{
			return .commandFailed(
				"The Groves authentication helper was terminated before authentication could complete. Rebuild or reinstall Groves and verify the helper's code signing and provisioning profile.\n\n\(message)"
			)
		}
		if lowercasedMessage.contains("authentication failed")
			|| lowercasedMessage.contains("permission denied")
			|| lowercasedMessage.contains("could not read username")
			|| lowercasedMessage.contains("terminal prompts disabled")
		{
			if configuration.globalConfigurationURL != nil {
				return .authentication(
					"Git authentication failed. Account verification does not verify repository access. Check repository permissions in Settings → Accounts.\n\n\(message)"
				)
			}
			return .authentication(message)
		}
		if lowercasedMessage.contains("could not resolve host")
			|| lowercasedMessage.contains("failed to connect")
			|| lowercasedMessage.contains("connection timed out")
			|| lowercasedMessage.contains("network is unreachable")
			|| lowercasedMessage.contains("connection reset")
		{
			return .network(message)
		}
		return .commandFailed(message)
	}

	private func redacted(_ message: String) -> String {
		let patterns = [
			(#"(?i)(https?://)[^/@\s]+@"#, "$1***@"),
			(#"\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b"#, "***"),
			(#"(?im)(authorization\s*:\s*(?:bearer|basic)\s+)\S+"#, "$1***"),
			(#"(?im)(\b(?:password|access_token|token)=)[^\s&]+"#, "$1***"),
		]
		return patterns.reduce(message) { result, pattern in
			guard let regex = try? NSRegularExpression(pattern: pattern.0) else { return result }
			let range = NSRange(result.startIndex..<result.endIndex, in: result)
			return regex.stringByReplacingMatches(in: result, range: range, withTemplate: pattern.1)
		}
	}
}
