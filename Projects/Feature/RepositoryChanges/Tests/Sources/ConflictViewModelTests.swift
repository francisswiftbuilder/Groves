import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct ConflictViewModelTests {
	private struct ContentFailure: LocalizedError, Sendable {
		var errorDescription: String? { "Conflict content unavailable" }
	}

	@Test
	func testFailedContentLoadReportsError() async throws {
		var messages: [String] = []
		let viewModel = makeViewModel(
			operationsUseCase: ConflictOperationsUseCaseStub(
				conflictContentOperation: { _, _ in throw ContentFailure() }
			),
			didReceiveError: { messages.append($0) }
		)

		viewModel.didSelectConflict(makeConflict())
		try await waitUntil { !messages.isEmpty }

		#expect(messages == ["Conflict content unavailable"])
		#expect(viewModel.content == nil)
		#expect(!viewModel.isLoadingContent)
	}

	@Test(arguments: [GitConflictResolution.ours, .theirs])
	func wholeFileResolutionRequiresAndForwardsTheReviewedContents(resolution: GitConflictResolution)
		async throws
	{
		let conflict = makeConflict()
		let displayed = GitConflictContent(
			base: "base", current: "current", incoming: "incoming", workingTree: "reviewed", hunks: [])
		let repository = URL(fileURLWithPath: "/tmp/GrovesConflict")
		let snapshot = RepositorySnapshot(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal, tags: [], stashes: [], fileTree: [])
		var results: [RepositorySnapshot] = []
		let viewModel = makeViewModel(
			operationsUseCase: ConflictOperationsUseCaseStub(
				conflictContentOperation: { _, _ in displayed },
				resolveOperation: { selected, action, expected, url in
					#expect(selected == conflict)
					#expect(action == resolution)
					#expect(expected == displayed)
					#expect(url == repository)
					return snapshot
				}),
			repositoryURL: repository, didProduceSnapshot: { results.append($0) })

		viewModel.didSelectConflict(conflict)
		#expect(viewModel.isLoadingContent)
		#expect(!viewModel.canResolveFile(conflict))
		viewModel.didResolve(conflict, using: resolution)
		#expect(!viewModel.isLoading)
		try await waitUntil { viewModel.content == displayed && !viewModel.isLoadingContent }

		#expect(viewModel.canResolveFile(conflict))
		viewModel.didResolve(conflict, using: resolution)
		try await waitUntil { !viewModel.isLoading }

		#expect(results.count == 1)
		#expect(results.first?.operationState == .normal)
	}

	@Test
	func testOpenInEditorUsesInjectedBundleIdentifier() throws {
		let repositoryURL = try makeRepositoryDirectory()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let conflict = makeConflict()
		let fileURL = repositoryURL.appending(path: conflict.path)
		try Data("conflict".utf8).write(to: fileURL)
		var openedFileURL: URL?
		var openedBundleIdentifier: String?
		let viewModel = makeViewModel(
			repositoryURL: repositoryURL,
			openExternalEditor: { fileURL, bundleIdentifier in
				openedFileURL = fileURL
				openedBundleIdentifier = bundleIdentifier
			},
			externalEditorBundleIdentifier: { "com.example.Editor" }
		)

		viewModel.didOpenInEditor(conflict)

		#expect(openedFileURL == fileURL)
		#expect(openedBundleIdentifier == "com.example.Editor")
	}

	@Test
	func testOpenInEditorTreatsEmptyBundleIdentifierAsSystemDefault() throws {
		let repositoryURL = try makeRepositoryDirectory()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let conflict = makeConflict()
		try Data("conflict".utf8).write(to: repositoryURL.appending(path: conflict.path))
		var invocationCount = 0
		var openedBundleIdentifier: String? = "unset"
		let viewModel = makeViewModel(
			repositoryURL: repositoryURL,
			openExternalEditor: { _, bundleIdentifier in
				invocationCount += 1
				openedBundleIdentifier = bundleIdentifier
			},
			externalEditorBundleIdentifier: { "" }
		)

		viewModel.didOpenInEditor(conflict)

		#expect(invocationCount == 1)
		#expect(openedBundleIdentifier == nil)
	}

	private func makeRepositoryDirectory() throws -> URL {
		let repositoryURL = FileManager.default.temporaryDirectory.appending(
			path: "GrovesConflictEditor-\(UUID().uuidString)",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		return repositoryURL
	}

	private func makeConflict() -> GitConflict {
		GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
	}

	private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func makeViewModel(
		operationsUseCase: ConflictOperationsUseCaseStub = ConflictOperationsUseCaseStub(),
		repositoryURL: URL = URL(fileURLWithPath: "/tmp/Groves"),
		openExternalEditor: (@MainActor (URL, String?) throws -> Void)? = nil,
		externalEditorBundleIdentifier: @escaping @MainActor () -> String? = { nil },
		didReceiveError: @escaping @MainActor (String) -> Void = { _ in },
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in }
	) -> ConflictViewModel {
		ConflictViewModel(
			dependencies: ConflictViewModel.Dependencies(
				contentUseCase: ChangesContentUseCaseStub(),
				operationsUseCase: operationsUseCase,
				openExternalEditor: openExternalEditor,
				repositoryURL: { repositoryURL },
				externalEditorBundleIdentifier: externalEditorBundleIdentifier
			),
			actions: ConflictViewModel.Actions(
				didProduceSnapshot: didProduceSnapshot,
				didReceiveError: didReceiveError
			)
		)
	}
}
