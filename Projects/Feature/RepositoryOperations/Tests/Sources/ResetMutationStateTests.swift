import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct ResetMutationStateTests {
	private final class Location {
		var url = URL(fileURLWithPath: "/tmp/GrovesOriginal")
	}

	private actor Recorder {
		private(set) var urls: [URL] = []
		private(set) var contexts: [GitResetContext] = []
		func append(_ url: URL, context: GitResetContext) {
			urls.append(url)
			contexts.append(context)
		}
	}

	@Test(arguments: [GitResetMode.mixed, .hard])
	func resetDiscardsConfirmationsBeforeTheRepositoryIsReplaced(mode: GitResetMode) async throws {
		let location = Location()
		let recorder = Recorder()
		let value = snapshot()
		let model = makeModel(
			location: location,
			operation: { _, _, context, url in
				await recorder.append(url, context: context)
				return value
			})
		model.didPresentReset(commit())
		model.resetMode = mode
		if mode == .hard { model.didConfirmReset() }
		model.reset()
		location.url = URL(fileURLWithPath: "/tmp/GrovesReplacement")
		model.apply(snapshot())
		model.didConfirmReset()
		model.didConfirmPendingConfirmation()
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.pendingReset == nil)
		#expect(model.pendingConfirmation == nil)
		#expect(model.resetMode == .mixed)
		let urls = await recorder.urls
		#expect(urls.isEmpty)
	}

	@Test(arguments: ["repository", "branch", "head"])
	func confirmationRejectsAChangedRepositoryBranchOrHEAD(change: String) async throws {
		let location = Location()
		let recorder = Recorder()
		let value = snapshot()
		var errors: [String] = []
		let model = makeModel(
			location: location,
			operation: { _, _, context, url in
				await recorder.append(url, context: context)
				return value
			}, didReceiveError: { errors.append($0) })
		model.didPresentReset(commit())
		model.resetMode = .hard
		model.didConfirmReset()
		if change == "repository" {
			location.url = URL(fileURLWithPath: "/tmp/GrovesReplacement")
		} else {
			model.apply(
				snapshot(
					name: change == "branch" ? "other" : "main",
					hash: change == "head"
						? String(repeating: "b", count: 40) : String(repeating: "a", count: 40)))
		}

		model.didConfirmPendingConfirmation()
		try await Task.sleep(for: .milliseconds(30))

		let urls = await recorder.urls
		#expect(urls.isEmpty)
		#expect(errors.count == 1)
		#expect(model.pendingConfirmation == nil)
	}

	@Test
	func resetSubmissionsAreGatedSynchronouslyAndCarryTheConfirmedHEAD() async throws {
		let gate = OperationsMutationGate()
		let recorder = Recorder()
		let model = makeModel(operation: { _, _, context, url in
			await recorder.append(url, context: context)
			return try await gate.load()
		})
		model.didPresentReset(commit())
		model.didConfirmReset()
		#expect(model.isLoading)
		model.didConfirmReset()
		try await gate.waitForRequests(1)
		try await Task.sleep(for: .milliseconds(30))
		let count = await gate.requestCount
		let contexts = await recorder.contexts
		#expect(count == 1)
		#expect(
			contexts == [GitResetContext(branchName: "main", headHash: String(repeating: "a", count: 40))]
		)
		for index in 0..<count { await gate.resume(index, with: .success(snapshot())) }
		try await waitUntil { !model.isLoading }
		#expect(model.pendingReset == nil)
	}

	@Test
	func failedResetKeepsItsPresentationAndCanBeRetried() async throws {
		let gate = OperationsMutationGate()
		let model = makeModel(operation: { _, _, _, _ in try await gate.load() })
		model.didPresentReset(commit())
		model.resetMode = .soft
		let presentationID = model.pendingReset?.id
		model.didConfirmReset()
		try await gate.waitForRequests(1)
		await gate.resume(0, with: .failure(GitRepositoryError.commandFailed("Repository busy")))
		try await waitUntil { !model.isLoading }

		#expect(model.pendingReset?.id == presentationID)
		#expect(model.resetMode == .soft)
		#expect(model.mutationErrorMessage?.contains("busy") == true)
		model.didConfirmReset()
		#expect(model.mutationErrorMessage == nil)
		try await gate.waitForRequests(2)
		await gate.resume(1, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }
		#expect(model.pendingReset == nil)
	}

	@Test
	func cancelledResetCannotFinishANewerRequestOrDismissItsForm() async throws {
		let gate = OperationsMutationGate()
		let model = makeModel(operation: { _, _, _, _ in try await gate.load() })
		model.didPresentReset(commit())
		model.didConfirmReset()
		try await gate.waitForRequests(1)
		model.onDisappear()
		model.didPresentReset(commit())
		let presentationID = model.pendingReset?.id
		model.didConfirmReset()
		try await gate.waitForRequests(2)

		await gate.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.isLoading)
		#expect(model.pendingReset?.id == presentationID)
		await gate.resume(1, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }
	}

	@Test
	func staleFailureRecoveryDoesNotPublishAfterReset() async throws {
		let location = Location()
		let gate = OperationsMutationGate()
		var published = 0
		let model = makeModel(
			location: location,
			content: OperationsContentUseCaseStub(snapshotOperation: { _ in try await gate.load() }),
			operation: { _, _, _, _ in throw GitRepositoryError.commandFailed("Failure") },
			didProduceSnapshot: { _ in published += 1 })
		model.didPresentReset(commit())
		model.didConfirmReset()
		try await gate.waitForRequests(1)
		model.reset()
		location.url = URL(fileURLWithPath: "/tmp/GrovesReplacement")
		await gate.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(published == 0)
		#expect(!model.isLoading)
	}

	@Test
	func detachedHEADDisablesResetMergeAndRebase() {
		let model = makeModel(operation: { _, _, _, _ in fatalError() })
		model.apply(snapshot(state: .detachedHead))
		model.didPresentReset(commit())
		let other = GitBranch(name: "other", shortHash: "abcdef0", upstream: nil, isCurrent: false)
		#expect(model.pendingReset == nil)
		#expect(!model.canMergeBranch(other))
		#expect(!model.canRebaseOnto(other))
	}

	@Test
	func releasingTheModelCancelsItsTaskWithoutRetainingTheForm() async throws {
		let gate = OperationsMutationGate()
		var model: RepositoryOperationViewModel? = makeModel(operation: { _, _, _, _ in
			try await gate.load()
		})
		weak var weakModel = model
		model?.didPresentReset(commit())
		model?.didConfirmReset()
		try await gate.waitForRequests(1)

		model = nil

		#expect(weakModel == nil)
		await gate.resume(0, with: .success(snapshot()))
	}

	private func makeModel(
		location: Location = Location(), content: OperationsContentUseCaseStub? = nil,
		operation:
			@escaping @Sendable (String, GitResetMode, GitResetContext, URL) async throws ->
			RepositorySnapshot,
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in },
		didReceiveError: @escaping @MainActor (String) -> Void = { _ in }
	) -> RepositoryOperationViewModel {
		let value = snapshot()
		let model = RepositoryOperationViewModel(
			dependencies: .init(
				contentUseCase: content ?? OperationsContentUseCaseStub(snapshotOperation: { _ in value }),
				referencesUseCase: OperationsReferencesUseCaseStub(),
				operationsUseCase: OperationsUseCaseStub(resetOperation: operation),
				repositoryURL: { location.url }),
			actions: .init(
				didProduceSnapshot: didProduceSnapshot, didReceiveError: didReceiveError,
				didRequestViewConflicts: { _ in }))
		model.apply(value)
		return model
	}

	private func snapshot(
		name: String = "main", hash: String = String(repeating: "a", count: 40),
		state: RepositoryOperationState = .normal
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [], amendChanges: [], commits: [],
			branches: [
				GitBranch(
					name: name, shortHash: String(hash.prefix(7)), hash: hash, upstream: nil, isCurrent: true)
			], remotes: [], operationState: state, tags: [], stashes: [], fileTree: [])
	}

	private func commit() -> GitCommit {
		GitCommit(
			hash: String(repeating: "c", count: 40), shortHash: "ccccccc", parentHashes: [],
			author: "Review", date: .distantPast, references: [], subject: "Selected commit", body: "")
	}

	private func waitUntil(_ condition: () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for reset state")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
