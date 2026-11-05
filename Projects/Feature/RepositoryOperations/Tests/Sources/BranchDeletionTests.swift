import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct BranchDeletionTests {
	private actor Recorder {
		var calls: [String] = []
		var failure: String?

		init(failure: String? = nil) { self.failure = failure }
		func record(_ call: String) throws {
			calls.append(call)
			if call == failure { throw GitRepositoryError.commandFailed("Deletion rejected") }
		}
	}

	@Test(arguments: [false, true])
	func localDeletionOnlyRemovesTheUpstreamWhenSelected(paired: Bool) async throws {
		let recorder = Recorder()
		let snapshot = snapshot()
		let model = references(recorder: recorder, snapshot: snapshot)
		let branch = try #require(snapshot.branches.first)
		model.didPresentBranchDeletion(branch)
		#expect(model.deletionRemoteBranch?.fullName == "origin/feature")
		model.didConfirmPendingConfirmation(deleteLinkedBranch: paired)
		try await waitUntil { !model.isLoading }
		#expect(
			await recorder.calls
				== (paired ? ["local:feature", "remote:origin/feature"] : ["local:feature"]))
		#expect(model.deletionRemoteBranch == nil)
	}

	@Test(arguments: [false, true])
	func remoteDeletionOnlyRemovesTrackingLocalsWhenSelected(paired: Bool) async throws {
		let recorder = Recorder()
		let snapshot = snapshot()
		let model = remotes(recorder: recorder, snapshot: snapshot)
		let remote = try #require(snapshot.remotes.first?.branches.first)
		model.didPresentBranchDeletion(remote)
		#expect(model.deletionLocalBranches.map(\.name) == ["feature"])
		model.didConfirmPendingConfirmation(deleteLinkedBranch: paired)
		try await waitUntil { !model.isLoading }
		#expect(
			await recorder.calls
				== (paired ? ["local:feature", "remote:origin/feature"] : ["remote:origin/feature"]))
	}

	@Test
	func multipleTrackingLocalsAreListedAndDeletedWithoutUsingMatchingNames() async throws {
		let recorder = Recorder()
		let snapshot = snapshot(branches: [
			local("renamed-local"), local("feature", upstream: "another/feature"), local("another-local"),
		])
		let model = remotes(recorder: recorder, snapshot: snapshot)
		let remote = try #require(snapshot.remotes.first?.branches.first)
		model.didPresentBranchDeletion(remote)
		#expect(model.deletionLocalBranches.map(\.name) == ["another-local", "renamed-local"])
		model.didConfirmPendingConfirmation(deleteLinkedBranch: true)
		try await waitUntil { !model.isLoading }
		#expect(
			await recorder.calls == [
				"local:another-local", "local:renamed-local", "remote:origin/feature",
			])
	}

	@Test
	func checkedOutTrackingBranchPreventsPairedDeletion() async throws {
		let recorder = Recorder()
		let snapshot = snapshot(branches: [local("feature", current: true)])
		var errors: [String] = []
		let model = remotes(recorder: recorder, snapshot: snapshot) { errors.append($0) }
		let remote = try #require(snapshot.remotes.first?.branches.first)
		model.didPresentBranchDeletion(remote)
		model.didConfirmPendingConfirmation(deleteLinkedBranch: true)
		#expect(await recorder.calls.isEmpty)
		#expect(errors.count == 1)
	}

	@Test
	func failedLocalDeletionKeepsTheRemoteBranch() async throws {
		let recorder = Recorder(failure: "local:feature")
		let snapshot = snapshot()
		let model = remotes(recorder: recorder, snapshot: snapshot)
		let remote = try #require(snapshot.remotes.first?.branches.first)
		model.didPresentBranchDeletion(remote)
		model.didConfirmPendingConfirmation(deleteLinkedBranch: true)
		try await waitUntil { !model.isLoading }
		#expect(await recorder.calls == ["local:feature"])
		#expect(model.mutationErrorMessage?.contains("Deletion rejected") == true)
	}

	@Test
	func remoteFailureReportsThatLocalDeletionAlreadySucceeded() async throws {
		let recorder = Recorder(failure: "remote:origin/feature")
		let snapshot = snapshot()
		let model = references(recorder: recorder, snapshot: snapshot)
		model.didPresentBranchDeletion(try #require(snapshot.branches.first))
		model.didConfirmPendingConfirmation(deleteLinkedBranch: true)
		try await waitUntil { !model.isLoading }
		#expect(await recorder.calls == ["local:feature", "remote:origin/feature"])
		#expect(model.mutationErrorMessage?.contains("local branch “feature” was deleted") == true)
	}

	@Test
	func changedTrackingBranchIsNotDeletedFromAnOlderConfirmation() async throws {
		let recorder = Recorder()
		let snapshot = snapshot()
		let model = remotes(recorder: recorder, snapshot: snapshot)
		let remote = try #require(snapshot.remotes.first?.branches.first)
		model.didPresentBranchDeletion(remote)
		model.apply(self.snapshot(branches: [local("feature", current: true)]))
		model.didConfirmPendingConfirmation(deleteLinkedBranch: true)
		#expect(await recorder.calls.isEmpty)
	}

	@Test
	func untrackedSameNameDoesNotBecomeACounterpart() throws {
		let snapshot = snapshot(branches: [local("feature", upstream: nil)])
		let model = references(recorder: Recorder(), snapshot: snapshot)
		model.didPresentBranchDeletion(try #require(snapshot.branches.first))
		#expect(model.deletionRemoteBranch == nil)
		let remoteModel = remotes(recorder: Recorder(), snapshot: snapshot)
		remoteModel.didPresentBranchDeletion(try #require(snapshot.remotes.first?.branches.first))
		#expect(remoteModel.deletionLocalBranches.isEmpty)
	}

	private func useCase(recorder: Recorder, snapshot: RepositorySnapshot)
		-> OperationsReferencesUseCaseStub
	{
		var useCase = OperationsReferencesUseCaseStub()
		useCase.deleteBranchOperation = { name, _ in
			try await recorder.record("local:" + name)
			return snapshot
		}
		useCase.deleteRemoteBranchOperation = { branch, _ in
			try await recorder.record("remote:" + branch.fullName)
			return snapshot
		}
		return useCase
	}

	private func references(recorder: Recorder, snapshot: RepositorySnapshot)
		-> RepositoryReferencesViewModel
	{
		let model = RepositoryReferencesViewModel(
			dependencies: .init(
				contentUseCase: OperationsContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				referencesUseCase: useCase(recorder: recorder, snapshot: snapshot),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: { _ in }))
		model.apply(snapshot)
		return model
	}

	private func remotes(
		recorder: Recorder, snapshot: RepositorySnapshot,
		didReceiveError: @escaping @MainActor (String) -> Void = { _ in }
	) -> RemotesViewModel {
		let model = RemotesViewModel(
			dependencies: .init(
				contentUseCase: OperationsContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				referencesUseCase: useCase(recorder: recorder, snapshot: snapshot),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: didReceiveError))
		model.apply(snapshot)
		return model
	}

	private func snapshot(branches: [GitBranch]? = nil) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [], amendChanges: [], commits: [], branches: branches ?? [local("feature")],
			remotes: [
				GitRemote(
					name: "origin", fetchURL: "https://example.com/repo.git", pushURL: nil,
					branches: [
						.init(
							name: "feature", fullName: "origin/feature", remoteName: "origin", shortHash: "abc",
							hash: "abcdef")
					])
			],
			operationState: .normal, tags: [], stashes: [], fileTree: [])
	}

	private func local(_ name: String, upstream: String? = "origin/feature", current: Bool = false)
		-> GitBranch
	{
		.init(name: name, shortHash: "abc", hash: "abcdef", upstream: upstream, isCurrent: current)
	}

	private func waitUntil(_ condition: () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while !condition() {
			guard clock.now < deadline else { throw CancellationError() }
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
