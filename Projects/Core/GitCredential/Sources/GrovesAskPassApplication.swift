import Foundation

@MainActor
public final class GrovesAskPassApplication {
	private let brokerClient: GitCredentialBrokerClient?
	private let makePresenter: @MainActor (Int32?) -> any GitCredentialPromptPresenting
	private let readStandardInput: @MainActor () -> Data
	private let writeStandardOutput: @MainActor (Data) -> Void
	private let writeStandardError: @MainActor (Data) -> Void

	public init(
		brokerClient: GitCredentialBrokerClient? = nil,
		makePresenter: @escaping @MainActor (Int32?) -> any GitCredentialPromptPresenting,
		readStandardInput: @escaping @MainActor () -> Data = {
			FileHandle.standardInput.readDataToEndOfFile()
		},
		writeStandardOutput: @escaping @MainActor (Data) -> Void = {
			FileHandle.standardOutput.write($0)
		},
		writeStandardError: @escaping @MainActor (Data) -> Void = {
			FileHandle.standardError.write($0)
		}
	) {
		self.brokerClient = brokerClient
		self.makePresenter = makePresenter
		self.readStandardInput = readStandardInput
		self.writeStandardOutput = writeStandardOutput
		self.writeStandardError = writeStandardError
	}

	public func run(arguments: [String], environment: [String: String]) -> Int32 {
		do {
			if arguments.first == "credential" {
				try runCredentialHelper(
					operation: arguments.dropFirst().first ?? "",
					environment: environment
				)
				return EXIT_SUCCESS
			}
			let prompt = arguments.first ?? "Authentication required"
			let value = try runAskPass(prompt: prompt, environment: environment)
			writeStandardOutput(Data((value + "\n").utf8))
			return EXIT_SUCCESS
		} catch is CancellationError {
			writeStandardError(Data("GROVES_ASKPASS_CANCELLED\n".utf8))
			return EXIT_FAILURE
		} catch {
			let diagnostic: String
			if let error = error as? GitCredentialStoreError {
				diagnostic = error.diagnosticDescription
			} else if let error = error as? GitCredentialBrokerError {
				diagnostic = error.diagnosticDescription
			} else {
				diagnostic = "error-type=\(String(reflecting: type(of: error)))"
			}
			writeStandardError(Data("Groves authentication helper failed (\(diagnostic)).\n".utf8))
			if arguments.prefix(2) == ["credential", "get"] {
				writeStandardOutput(Data("quit=true\n\n".utf8))
			}
			return EXIT_FAILURE
		}
	}

	private func runAskPass(prompt: String, environment: [String: String]) throws -> String {
		let client = try client(in: environment)
		try client.validateConnection()
		let kind = GitCredentialPromptKind(prompt: prompt)
		let presenter = makePresenter(parentProcessIdentifier(in: environment))
		let answer = try presenter.presentPrompt(prompt, kind: kind)
		if kind == .secret {
			try client.setShouldSave(answer.shouldSave)
		}
		return answer.value
	}

	private func runCredentialHelper(operation: String, environment: [String: String]) throws {
		guard let operation = GitCredentialHelperOperation(rawValue: operation) else { return }
		let input = String(decoding: readStandardInput(), as: UTF8.self)
		guard GitCredentialHelper.supports(input: input) else { return }
		guard
			let response = try client(in: environment).credential(
				operation: operation,
				input: input
			)
		else { return }
		writeStandardOutput(Data(response.utf8))
	}

	private func client(in environment: [String: String]) throws -> GitCredentialBrokerClient {
		if let brokerClient { return brokerClient }
		guard let socketPath = environment["GROVES_CREDENTIAL_SOCKET"],
			let operationID = environment["GROVES_OPERATION_IDENTIFIER"]
		else { throw GitCredentialBrokerError.unavailable }
		return try GitCredentialBrokerClient(
			socketPath: socketPath, operationID: operationID,
			parentApplicationURL: GitCredentialPeerVerification.parentApplicationURL(
				for: Bundle.main.bundleURL))
	}

	private func parentProcessIdentifier(in environment: [String: String]) -> Int32? {
		environment["GROVES_PARENT_PROCESS_IDENTIFIER"].flatMap(Int32.init)
	}
}
