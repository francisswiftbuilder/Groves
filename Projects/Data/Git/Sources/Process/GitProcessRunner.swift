import CoreGitCredential
import DomainGitInterface
import Foundation

actor GitProcessRunner {
	private let configuration: GitProcessConfiguration
	private let credentialStore = GitCredentialStore()
	private let decisionStore = GitCredentialSaveDecisionStore()

	init(configuration: GitProcessConfiguration = GitProcessConfiguration()) {
		self.configuration = configuration
	}

	func requestRun(
		arguments: [String],
		at repositoryURL: URL,
		standardInput: String? = nil,
		environment: [String: String] = [:],
		acceptedTerminationStatuses: Set<Int32> = [0],
		isNetworkOperation: Bool = false
	) async throws -> GitCommandResult {
		let operationID = UUID().uuidString
		var didSucceed = false
		defer {
			if didSucceed == false {
				try? credentialStore.discardPending(operationID: operationID)
				decisionStore.discard(operationID: operationID)
			}
		}

		let trustScope = isNetworkOperation ? try? GitSSHTrustScope() : nil
		defer { trustScope?.remove() }

		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory
			.appendingPathComponent("Trees-\(UUID().uuidString)", isDirectory: true)
		let standardOutputURL = temporaryDirectory.appendingPathComponent("stdout")
		let standardErrorURL = temporaryDirectory.appendingPathComponent("stderr")
		let standardInputURL = temporaryDirectory.appendingPathComponent("stdin")

		try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		fileManager.createFile(atPath: standardOutputURL.path, contents: nil)
		fileManager.createFile(atPath: standardErrorURL.path, contents: nil)

		defer {
			try? fileManager.removeItem(at: temporaryDirectory)
		}

		let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
		let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
		let standardInputHandle: FileHandle?
		if let standardInput {
			try Data(standardInput.utf8).write(to: standardInputURL)
			standardInputHandle = try FileHandle(forReadingFrom: standardInputURL)
		} else {
			standardInputHandle = nil
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments =
			[
				"-c",
				"export TREES_PARENT_PROCESS_IDENTIFIER=$$; exec /usr/bin/env \"$@\"",
				"TreesGit",
			]
			+ gitArguments(
				arguments,
				repositoryURL: repositoryURL,
				isNetworkOperation: isNetworkOperation
			)
		process.environment = processEnvironment(
			merging: environment,
			isNetworkOperation: isNetworkOperation,
			operationID: operationID,
			trustScope: trustScope
		)
		process.standardOutput = standardOutputHandle
		process.standardError = standardErrorHandle
		process.standardInput = standardInputHandle

		let terminationStatus = try await requestTerminationStatus(
			for: process,
			standardInputHandle: standardInputHandle,
			standardOutputHandle: standardOutputHandle,
			standardErrorHandle: standardErrorHandle,
			timeout: isNetworkOperation ? configuration.networkPolicy.operationTimeout : nil
		)
		let standardOutputData = try Data(contentsOf: standardOutputURL)
		let standardErrorData = try Data(contentsOf: standardErrorURL)
		let standardOutput = String(decoding: standardOutputData, as: UTF8.self)
		let standardError = String(decoding: standardErrorData, as: UTF8.self)

		guard acceptedTerminationStatuses.contains(terminationStatus) else {
			if Task.isCancelled || standardError.contains("TREES_ASKPASS_CANCELLED") {
				throw CancellationError()
			}
			throw repositoryError(for: standardError)
		}
		commitPendingCredentials(operationID: operationID)
		decisionStore.discard(operationID: operationID)
		didSucceed = true

		return GitCommandResult(
			standardOutputData: standardOutputData,
			standardOutput: standardOutput,
			standardError: standardError
		)
	}

	private func commitPendingCredentials(operationID: String) {
		do {
			try credentialStore.commitPending(operationID: operationID)
		} catch {
			try? credentialStore.discardPending(operationID: operationID)
		}
	}

	private func processEnvironment(
		merging environment: [String: String],
		isNetworkOperation: Bool,
		operationID: String,
		trustScope: GitSSHTrustScope?
	) -> [String: String] {
		var result = ProcessInfo.processInfo.environment
		if isNetworkOperation {
			let policy = configuration.networkPolicy
			result["GIT_HTTP_LOW_SPEED_LIMIT"] = String(policy.lowSpeedLimit)
			result["GIT_HTTP_LOW_SPEED_TIME"] = String(Int(policy.lowSpeedTime))
			result["GIT_SSH_COMMAND"] =
				([
					"ssh",
					"-o ConnectTimeout=\(Int(policy.sshConnectTimeout))",
					"-o ServerAliveInterval=\(Int(policy.sshServerAliveInterval))",
					"-o ServerAliveCountMax=\(policy.sshServerAliveCountMax)",
				] + (trustScope?.sshOptions ?? [])).joined(separator: " ")
			result["GIT_TERMINAL_PROMPT"] = "0"
			if let helperURL = configuration.askPassHelperURL {
				result["GIT_ASKPASS"] = helperURL.path
				result["SSH_ASKPASS"] = helperURL.path
				result["SSH_ASKPASS_REQUIRE"] = "force"
				result["TREES_OPERATION_IDENTIFIER"] = operationID
			}
		}
		return result.merging(environment) { _, new in new }
	}

	private func gitArguments(
		_ arguments: [String],
		repositoryURL: URL,
		isNetworkOperation: Bool
	) -> [String] {
		var result = ["git"]
		if isNetworkOperation, let helperURL = configuration.askPassHelperURL {
			let escapedPath = helperURL.path.replacingOccurrences(of: "'", with: "'\\''")
			result += ["-c", "credential.helper=!'\(escapedPath)' credential"]
		}
		result += ["-C", repositoryURL.path]
		result += arguments
		return result
	}

	private func requestTerminationStatus(
		for process: Process,
		standardInputHandle: FileHandle?,
		standardOutputHandle: FileHandle,
		standardErrorHandle: FileHandle,
		timeout: TimeInterval?
	) async throws -> Int32 {
		guard let timeout else {
			return try await waitForTermination(
				of: process,
				standardInputHandle: standardInputHandle,
				standardOutputHandle: standardOutputHandle,
				standardErrorHandle: standardErrorHandle
			)
		}

		return try await withThrowingTaskGroup(of: Int32.self) { group in
			group.addTask {
				try await self.waitForTermination(
					of: process,
					standardInputHandle: standardInputHandle,
					standardOutputHandle: standardOutputHandle,
					standardErrorHandle: standardErrorHandle
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
		standardInputHandle: FileHandle?,
		standardOutputHandle: FileHandle,
		standardErrorHandle: FileHandle
	) async throws -> Int32 {
		let lifecycle = GitProcessLifecycle(
			process: process,
			gracePeriod: configuration.terminationGracePeriod
		)
		try Task.checkCancellation()
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				lifecycle.start(
					onTermination: { continuation.resume(returning: $0) },
					onFailure: { continuation.resume(throwing: $0) }
				)
				standardInputHandle?.closeFile()
				standardOutputHandle.closeFile()
				standardErrorHandle.closeFile()
			}
		} onCancel: {
			lifecycle.cancel()
		}
	}

	private func repositoryError(for standardError: String) -> GitRepositoryError {
		let message = redacted(standardError).trimmingCharacters(in: .whitespacesAndNewlines)
		let lowercasedMessage = message.lowercased()
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
		if lowercasedMessage.contains("authentication failed")
			|| lowercasedMessage.contains("permission denied")
			|| lowercasedMessage.contains("could not read username")
			|| lowercasedMessage.contains("terminal prompts disabled")
		{
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
		guard let regex = try? NSRegularExpression(pattern: #"(?i)(https?://)[^/@\s]+@"#) else {
			return message
		}
		let range = NSRange(message.startIndex..<message.endIndex, in: message)
		return regex.stringByReplacingMatches(in: message, range: range, withTemplate: "$1***@")
	}
}
