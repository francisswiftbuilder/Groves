import Foundation
import Testing

@testable import CoreGitCredential

@MainActor
@Suite(.serialized)
struct GrovesAskPassApplicationTests {
	@Test
	func acceptedPromptWritesTheAnswerToStandardOutput() throws {
		let store = makeStore()
		let presenter = GitCredentialPromptPresenterStub(
			answer: GitCredentialPromptAnswer(value: "groves", shouldSave: false)
		)
		var standardOutput = Data()
		var standardError = Data()
		defer { try? store.deleteAll() }
		let application = GrovesAskPassApplication(
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
		#expect(String(decoding: standardOutput, as: UTF8.self) == "groves\n")
		#expect(standardError.isEmpty)
	}

	@Test
	func cancelledPromptWritesTheCancellationMarker() throws {
		let store = makeStore()
		var standardOutput = Data()
		var standardError = Data()
		defer { try? store.deleteAll() }
		let application = GrovesAskPassApplication(
			credentialStore: store,
			decisionStore: makeDecisionStore(),
			makePresenter: { _ in GitCredentialPromptPresenterStub(answer: nil) },
			writeStandardOutput: { standardOutput.append($0) },
			writeStandardError: { standardError.append($0) }
		)

		let status = application.run(
			arguments: ["Password for 'https://github.com':"],
			environment: ["GROVES_OPERATION_IDENTIFIER": "operation"]
		)

		#expect(status == EXIT_FAILURE)
		#expect(standardOutput.isEmpty)
		#expect(String(decoding: standardError, as: UTF8.self) == "GROVES_ASKPASS_CANCELLED\n")
		#expect(try store.descriptors().isEmpty)
	}

	@Test
	func credentialModeReadsAndWritesTheGitCredentialProtocol() throws {
		let store = makeStore()
		let descriptor = GitCredentialDescriptor(
			kind: .https,
			host: "github.com",
			account: "groves"
		)
		var standardOutput = Data()
		defer { try? store.deleteAll() }
		try store.save(secret: "token", for: descriptor)
		let application = GrovesAskPassApplication(
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
				== "password=token\nusername=groves\n\n"
		)
	}

	@Test
	func keychainFailureWritesOnlySanitizedDiagnostic() {
		let store = GitCredentialStore(
			service: "Groves.Tests.private-account",
			securityClient: GitCredentialSecurityClientStub(),
			accessGroupResolver: {
				throw GitCredentialStoreError(
					operation: .resolveAccessGroup,
					status: errSecAuthFailed
				)
			}
		)
		var standardError = Data()
		let application = GrovesAskPassApplication(
			credentialStore: store,
			decisionStore: makeDecisionStore(),
			makePresenter: { _ in GitCredentialPromptPresenterStub(answer: nil) },
			readStandardInput: {
				Data("protocol=https\nhost=private.example\nusername=private-account\n\n".utf8)
			},
			writeStandardError: { standardError.append($0) }
		)

		let status = application.run(arguments: ["credential", "get"], environment: [:])
		let message = String(decoding: standardError, as: UTF8.self)

		#expect(status == EXIT_FAILURE)
		#expect(message.contains("stage=resolve-access-group"))
		#expect(message.contains("private.example") == false)
		#expect(message.contains("private-account") == false)
	}

	private func makeStore() -> GitCredentialStore {
		makeTestCredentialStore()
	}

	private func makeDecisionStore() -> GitCredentialSaveDecisionStore {
		GitCredentialSaveDecisionStore(suiteName: "Groves.Tests.\(UUID().uuidString)")
	}
}
