import Foundation

@MainActor
public final class GrovesAskPassApplication {
	private let credentialStore: GitCredentialStore
	private let decisionStore: GitCredentialSaveDecisionStore
	private let credentialHelper: GitCredentialHelper
	private let makePresenter: @MainActor (Int32?) -> any GitCredentialPromptPresenting
	private let readStandardInput: @MainActor () -> Data
	private let writeStandardOutput: @MainActor (Data) -> Void
	private let writeStandardError: @MainActor (Data) -> Void

	public init(
		credentialStore: GitCredentialStore = GitCredentialStore(),
		decisionStore: GitCredentialSaveDecisionStore = GitCredentialSaveDecisionStore(),
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
		self.credentialStore = credentialStore
		self.decisionStore = decisionStore
		self.makePresenter = makePresenter
		self.readStandardInput = readStandardInput
		self.writeStandardOutput = writeStandardOutput
		self.writeStandardError = writeStandardError
		credentialHelper = GitCredentialHelper(
			store: credentialStore,
			decisionStore: decisionStore
		)
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
			} else {
				diagnostic = "error-type=\(String(reflecting: type(of: error)))"
			}
			writeStandardError(Data("Groves authentication helper failed (\(diagnostic)).\n".utf8))
			return EXIT_FAILURE
		}
	}

	private func runAskPass(prompt: String, environment: [String: String]) throws -> String {
		let coordinator = GitCredentialPromptCoordinator(
			store: credentialStore,
			decisionStore: decisionStore,
			presenter: makePresenter(parentProcessIdentifier(in: environment))
		)
		return try coordinator.value(
			forPrompt: prompt,
			operationID: environment["GROVES_OPERATION_IDENTIFIER"]
		)
	}

	private func runCredentialHelper(operation: String, environment: [String: String]) throws {
		guard let operation = GitCredentialHelperOperation(rawValue: operation) else { return }
		let input = String(decoding: readStandardInput(), as: UTF8.self)
		guard
			let response = try credentialHelper.handle(
				operation: operation,
				input: input,
				operationID: environment["GROVES_OPERATION_IDENTIFIER"]
			)
		else { return }
		writeStandardOutput(Data(response.utf8))
	}

	private func parentProcessIdentifier(in environment: [String: String]) -> Int32? {
		environment["GROVES_PARENT_PROCESS_IDENTIFIER"].flatMap(Int32.init)
	}
}
