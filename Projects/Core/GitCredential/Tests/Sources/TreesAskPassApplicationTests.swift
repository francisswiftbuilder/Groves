import Foundation
import Testing

@testable import CoreGitCredential

@MainActor
@Suite(.serialized)
struct TreesAskPassApplicationTests {
	@Test
	func acceptedPromptWritesTheAnswerToStandardOutput() throws {
		let store = makeStore()
		let presenter = GitCredentialPromptPresenterStub(
			answer: GitCredentialPromptAnswer(value: "trees", shouldSave: false)
		)
		var standardOutput = Data()
		var standardError = Data()
		defer { try? store.deleteAll() }
		let application = TreesAskPassApplication(
			credentialStore: store,
			decisionStore: makeDecisionStore(),
			makePresenter: { _ in presenter },
			writeStandardOutput: { standardOutput.append($0) },
			writeStandardError: { standardError.append($0) }
		)

		let status = application.run(
			arguments: ["Username for 'https://github.com':"],
			environment: [:]
		)

		#expect(status == EXIT_SUCCESS)
		#expect(String(decoding: standardOutput, as: UTF8.self) == "trees\n")
		#expect(standardError.isEmpty)
	}

	@Test
	func cancelledPromptWritesTheCancellationMarker() throws {
		let store = makeStore()
		var standardOutput = Data()
		var standardError = Data()
		defer { try? store.deleteAll() }
		let application = TreesAskPassApplication(
			credentialStore: store,
			decisionStore: makeDecisionStore(),
			makePresenter: { _ in GitCredentialPromptPresenterStub(answer: nil) },
			writeStandardOutput: { standardOutput.append($0) },
			writeStandardError: { standardError.append($0) }
		)

		let status = application.run(
			arguments: ["Password for 'https://github.com':"],
			environment: ["TREES_OPERATION_IDENTIFIER": "operation"]
		)

		#expect(status == EXIT_FAILURE)
		#expect(standardOutput.isEmpty)
		#expect(String(decoding: standardError, as: UTF8.self) == "TREES_ASKPASS_CANCELLED\n")
		#expect(try store.descriptors().isEmpty)
	}

	@Test
	func credentialModeReadsAndWritesTheGitCredentialProtocol() throws {
		let store = makeStore()
		let descriptor = GitCredentialDescriptor(
			kind: .https,
			host: "github.com",
			account: "trees"
		)
		var standardOutput = Data()
		defer { try? store.deleteAll() }
		try store.save(secret: "token", for: descriptor)
		let application = TreesAskPassApplication(
			credentialStore: store,
			decisionStore: makeDecisionStore(),
			makePresenter: { _ in GitCredentialPromptPresenterStub(answer: nil) },
			readStandardInput: {
				Data("protocol=https\nhost=github.com\n\n".utf8)
			},
			writeStandardOutput: { standardOutput.append($0) }
		)

		let status = application.run(arguments: ["credential", "get"], environment: [:])

		#expect(status == EXIT_SUCCESS)
		#expect(
			String(decoding: standardOutput, as: UTF8.self)
				== "password=token\nusername=trees\n\n"
		)
	}

	private func makeStore() -> GitCredentialStore {
		GitCredentialStore(service: "Trees.Tests.\(UUID().uuidString)")
	}

	private func makeDecisionStore() -> GitCredentialSaveDecisionStore {
		GitCredentialSaveDecisionStore(suiteName: "Trees.Tests.\(UUID().uuidString)")
	}
}
