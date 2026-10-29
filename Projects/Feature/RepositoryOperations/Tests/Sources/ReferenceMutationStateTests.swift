import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct ReferenceMutationStateTests {
	@Test
	func tagCreationBlocksDuplicateSubmissionsSynchronously() async throws {
		let gate = OperationsMutationGate()
		let model = makeReferences(gate: gate)
		model.didPresentNewTag(for: commit())
		model.newTagName = "release"
		model.didRequestCreateTag()
		#expect(model.isLoading)
		model.didRequestCreateTag()
		try await gate.waitForRequests(1)
		try await Task.sleep(for: .milliseconds(30))
		let count = await gate.requestCount
		#expect(count == 1)
		for index in 0..<count { await gate.resume(index, with: .success(snapshot())) }
		try await waitUntil { !model.isLoading }
		#expect(model.pendingTagCommit == nil)
	}

	@Test
	func cancelledCreationCannotClearANewerDraftOrFinishItsRequest() async throws {
		let gate = OperationsMutationGate()
		let model = makeReferences(gate: gate)
		model.didPresentNewTag(for: commit())
		model.newTagName = "old"
		model.didRequestCreateTag()
		try await gate.waitForRequests(1)
		model.onDisappear()
		model.didPresentNewTag(for: commit())
		model.newTagName = "new"
		model.didRequestCreateTag()
		try await gate.waitForRequests(2)

		await gate.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.isLoading)
		#expect(model.newTagName == "new")
		#expect(model.pendingTagCommit != nil)
		await gate.resume(1, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }
		#expect(model.pendingTagCommit == nil)
	}

	@Test
	func anIdenticalReopenedFormIsNotDismissedByThePreviousSubmission() async throws {
		let gate = OperationsMutationGate()
		let model = makeReferences(gate: gate)
		model.didPresentNewTag(for: commit())
		model.newTagName = "release"
		model.didRequestCreateTag()
		try await gate.waitForRequests(1)
		model.didDismissNewTag()
		model.didPresentNewTag(for: commit())
		model.newTagName = "release"

		await gate.resume(0, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }

		#expect(model.newTagName == "release")
		#expect(model.pendingTagCommit != nil)
	}

	@Test
	func failedCreationPreservesInputsAndCanBeRetried() async throws {
		let gate = OperationsMutationGate()
		let model = makeReferences(gate: gate)
		model.didPresentNewTag(for: commit())
		model.newTagName = "release"
		model.newTagMessage = "Keep these notes"
		model.didRequestCreateTag()
		try await gate.waitForRequests(1)
		await gate.resume(0, with: .failure(GitRepositoryError.commandFailed("Tag already exists")))
		try await waitUntil { !model.isLoading }

		#expect(model.newTagName == "release")
		#expect(model.newTagMessage == "Keep these notes")
		#expect(model.pendingTagCommit != nil)
		#expect(model.mutationErrorMessage?.contains("already exists") == true)
		model.didRequestCreateTag()
		#expect(model.mutationErrorMessage == nil)
		try await gate.waitForRequests(2)
		await gate.resume(1, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }
		#expect(model.pendingTagCommit == nil)
	}

	@Test
	func cancelledBranchCreationCannotDismissANewerBranchForm() async throws {
		let gate = OperationsMutationGate()
		let model = makeReferences(gate: gate)
		model.didPresentNewBranch()
		model.newBranchName = "old"
		model.didRequestCreateBranch()
		try await gate.waitForRequests(1)
		model.reset()
		model.didPresentNewBranch()
		model.newBranchName = "new"

		await gate.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.newBranchName == "new")
		#expect(model.isPresentingNewBranch)
		#expect(!model.isLoading)
	}

	@Test
	func staleFailureRecoveryDoesNotPublishAfterReset() async throws {
		let gate = OperationsMutationGate()
		let recovery = OperationsMutationGate()
		var published = 0
		let model = makeReferences(
			gate: gate,
			content: OperationsContentUseCaseStub(snapshotOperation: { _ in try await recovery.load() }),
			didProduceSnapshot: { _ in published += 1 })
		model.didPresentNewTag(for: commit())
		model.newTagName = "release"
		model.didRequestCreateTag()
		try await gate.waitForRequests(1)
		await gate.resume(0, with: .failure(GitRepositoryError.commandFailed("Failure")))
		try await recovery.waitForRequests(1)

		model.reset()
		await recovery.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(published == 0)
		#expect(!model.isLoading)
	}

	@Test
	func remoteEditorSurvivesFailureAndClosesOnlyAfterSuccessfulRetry() async throws {
		let gate = OperationsMutationGate()
		let model = makeRemotes(gate: gate)
		let remote = GitRemote(name: "origin", fetchURL: "https://old.example/repo", pushURL: nil)
		model.didPresentEditor(remote)
		model.didRequestUpdate(remote, fetchURL: "https://new.example/repo", pushURL: nil)
		#expect(model.isLoading)
		model.didRequestUpdate(remote, fetchURL: "https://new.example/repo", pushURL: nil)
		try await gate.waitForRequests(1)
		try await Task.sleep(for: .milliseconds(30))
		let count = await gate.requestCount
		#expect(count == 1)
		for index in 0..<count {
			await gate.resume(
				index, with: .failure(GitRepositoryError.commandFailed("Configuration locked")))
		}
		try await waitUntil { !model.isLoading }
		#expect(model.editorPresentation?.id == "edit-origin")
		#expect(model.mutationErrorMessage?.contains("locked") == true)

		model.didRequestUpdate(remote, fetchURL: "https://new.example/repo", pushURL: nil)
		try await gate.waitForRequests(2)
		await gate.resume(1, with: .success(snapshot()))
		try await waitUntil { !model.isLoading }
		#expect(model.editorPresentation == nil)
	}

	@Test
	func cancelledRemoteUpdateCannotDismissANewerEditor() async throws {
		let gate = OperationsMutationGate()
		let model = makeRemotes(gate: gate)
		let remote = GitRemote(name: "origin", fetchURL: "https://old.example/repo", pushURL: nil)
		model.didPresentEditor(remote)
		model.didRequestUpdate(remote, fetchURL: "https://first.example/repo", pushURL: nil)
		try await gate.waitForRequests(1)
		model.onDisappear()
		model.didPresentAddRemote()

		await gate.resume(0, with: .success(snapshot()))
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.editorPresentation?.id == "add")
		#expect(!model.isLoading)
	}

	private func makeReferences(
		gate: OperationsMutationGate,
		content: OperationsContentUseCaseStub? = nil,
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in }
	) -> RepositoryReferencesViewModel {
		var references = OperationsReferencesUseCaseStub()
		references.createTagOperation = { _, _, _, _ in try await gate.load() }
		references.createBranchOperation = { _, _, _ in try await gate.load() }
		let snapshot = snapshot()
		return RepositoryReferencesViewModel(
			dependencies: .init(
				contentUseCase: content
					?? OperationsContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				referencesUseCase: references,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }),
			actions: .init(didProduceSnapshot: didProduceSnapshot, didReceiveError: { _ in }))
	}

	private func makeRemotes(gate: OperationsMutationGate) -> RemotesViewModel {
		var references = OperationsReferencesUseCaseStub()
		references.updateRemoteOperation = { _, _, _, _ in try await gate.load() }
		let snapshot = snapshot()
		return RemotesViewModel(
			dependencies: .init(
				contentUseCase: OperationsContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				referencesUseCase: references,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: { _ in }))
	}

	private func waitUntil(_ condition: () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for operation state")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(5))
		}
	}

	private func snapshot() -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal, tags: [], stashes: [], fileTree: [])
	}

	private func commit() -> GitCommit {
		GitCommit(
			hash: "abcdef", shortHash: "abcdef", parentHashes: [], author: "Groves",
			date: .distantPast, references: [], subject: "Commit", body: "")
	}
}
