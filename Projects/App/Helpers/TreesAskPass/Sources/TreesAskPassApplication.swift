import CoreGitCredential
import Foundation

@MainActor
final class TreesAskPassApplication {
	private let credentialStore: GitCredentialStore
	private let decisionStore: GitCredentialSaveDecisionStore
	private let credentialHelper: GitCredentialHelper
	private let makePresenter: (Int32?) -> any AskPassPromptPresenting

	init(
		credentialStore: GitCredentialStore = GitCredentialStore(),
		decisionStore: GitCredentialSaveDecisionStore = GitCredentialSaveDecisionStore(),
		makePresenter: @escaping (Int32?) -> any AskPassPromptPresenting = {
			AppKitAskPassPromptPresenter(parentProcessIdentifier: $0)
		}
	) {
		self.credentialStore = credentialStore
		self.decisionStore = decisionStore
		self.makePresenter = makePresenter
		credentialHelper = GitCredentialHelper(store: credentialStore, decisionStore: decisionStore)
	}

	func run(arguments: [String], environment: [String: String]) -> Int32 {
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
			FileHandle.standardOutput.write(Data((value + "\n").utf8))
			return EXIT_SUCCESS
		} catch is CancellationError {
			FileHandle.standardError.write(Data("TREES_ASKPASS_CANCELLED\n".utf8))
			return EXIT_FAILURE
		} catch {
			FileHandle.standardError.write(Data("Trees authentication helper failed.\n".utf8))
			return EXIT_FAILURE
		}
	}

	private func runAskPass(prompt: String, environment: [String: String]) throws -> String {
		let kind = AskPassPromptKind(prompt: prompt)
		let descriptor = sshDescriptor(prompt: prompt)
		if kind == .secret, let descriptor, let secret = try credentialStore.secret(for: descriptor) {
			return secret
		}
		let presenter = makePresenter(parentProcessIdentifier(in: environment))
		let result = try presenter.presentPrompt(prompt, kind: kind)
		guard let operationID = environment["TREES_OPERATION_IDENTIFIER"], !operationID.isEmpty else {
			return result.value
		}
		decisionStore.setShouldSave(result.shouldSave, operationID: operationID)
		if kind == .secret, result.shouldSave, let descriptor {
			try credentialStore.savePending(
				secret: result.value,
				for: descriptor,
				operationID: operationID
			)
		}
		return result.value
	}

	private func runCredentialHelper(operation: String, environment: [String: String]) throws {
		guard let operation = GitCredentialHelperOperation(rawValue: operation) else { return }
		let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
		guard
			let response = try credentialHelper.handle(
				operation: operation,
				input: input,
				operationID: environment["TREES_OPERATION_IDENTIFIER"]
			)
		else { return }
		FileHandle.standardOutput.write(Data(response.utf8))
	}

	private func parentProcessIdentifier(in environment: [String: String]) -> Int32? {
		environment["TREES_PARENT_PROCESS_IDENTIFIER"].flatMap(Int32.init)
	}

	private func sshDescriptor(prompt: String) -> GitCredentialDescriptor? {
		guard prompt.localizedCaseInsensitiveContains("passphrase"),
			let firstQuote = prompt.firstIndex(of: "'"),
			let secondQuote = prompt[prompt.index(after: firstQuote)...].firstIndex(of: "'")
		else { return nil }
		let path = String(prompt[prompt.index(after: firstQuote)..<secondQuote])
		guard !path.isEmpty else { return nil }
		return .sshKey(at: path)
	}
}
