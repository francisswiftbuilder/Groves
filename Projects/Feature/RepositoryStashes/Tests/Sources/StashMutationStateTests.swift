import CoreRepositoryDiff
import DomainGitInterface
import Foundation
import Observation
import Testing

@testable import FeatureRepositoryStashes

@MainActor
struct StashMutationStateTests {
	private final class Location {
		var url = URL(fileURLWithPath: "/tmp/OriginalRepository")
	}

	private actor Backend: RepositoryStashesUseCase {
		var value: RepositoryStashMutationResult
		let gate: StashesUseCaseGate?
		private(set) var urls: [URL] = []
		private(set) var diffHashes: [String] = []
		private(set) var submittedMessages: [String] = []
		private(set) var submittedOptions: [Bool] = []
		init(
			value: RepositorySnapshot, outcome: RepositoryStashOutcome = .completed,
			gate: StashesUseCaseGate? = nil
		) {
			self.value = RepositoryStashMutationResult(outcome: outcome, snapshot: value)
			self.gate = gate
		}
		func loadDiff(for stash: GitStash, options: GitDiffOptions, at repositoryURL: URL) async throws
			-> String
		{
			diffHashes.append(stash.hash)
			return
				"diff --git a/\(stash.hash).txt b/\(stash.hash).txt\n--- a/\(stash.hash).txt\n+++ b/\(stash.hash).txt\n@@ -1 +1 @@\n-old\n+new\n"
		}
		func loadImageDiff(
			for stash: GitStash, path: String, previousPath: String?, at repositoryURL: URL
		) async throws -> GitImageDiff { GitImageDiff(before: nil, after: nil) }
		func createStash(message: String, includeUntracked: Bool, at repositoryURL: URL) async throws
			-> RepositoryStashMutationResult
		{
			submittedMessages.append(message)
			submittedOptions.append(includeUntracked)
			return try await mutate(at: repositoryURL)
		}
		func setResult(_ value: RepositoryStashMutationResult) { self.value = value }
		func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
			-> RepositoryStashMutationResult
		{
			try await mutate(at: repositoryURL)
		}
		func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
			-> RepositoryStashMutationResult
		{
			try await mutate(at: repositoryURL)
		}
		func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
			-> RepositoryStashMutationResult
		{
			try await mutate(at: repositoryURL)
		}
		private func mutate(at url: URL) async throws -> RepositoryStashMutationResult {
			let result = value
			urls.append(url)
			await gate?.enter()
			return result
		}
	}

	@Test
	func aChangedStashAtTheSameIndexReloadsItsPreview() async throws {
		let backend = Backend(value: snapshot())
		let model = makeModel(backend)
		defer { model.onDisappear() }
		model.apply(snapshot(stashes: [stash(hash: "A")]))
		try await waitUntil { !model.isLoadingDiff }
		model.apply(snapshot(stashes: [stash(hash: "B")]))
		try await Task.sleep(for: .milliseconds(30))
		let hashes = await backend.diffHashes
		#expect(hashes == ["A", "B"])
		#expect(model.selectedFile?.path == "B.txt")
	}

	@Test
	func completedPushDoesNotClearATextDraftWrittenDuringTheRequest() async throws {
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let backend = Backend(value: snapshot(), gate: gate)
		let model = makeModel(backend)
		defer { model.onDisappear() }
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "submitted"
		model.didRequestCreateStash()
		try await waitForCalls(1, in: gate)
		model.newStashMessage = "new draft"
		await gate.resumeCall(0)
		try await waitUntil { !model.isLoading }
		#expect(model.newStashMessage == "new draft")
	}

	@Test
	func cancelledPushCannotClearANewerDraftOrItsLoadingState() async throws {
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let backend = Backend(value: snapshot(), gate: gate)
		let model = makeModel(backend)
		defer { model.onDisappear() }
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "old"
		model.didRequestCreateStash()
		try await waitForCalls(1, in: gate)
		model.reset()
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "new"
		model.didRequestCreateStash()
		try await waitForCalls(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(30))
		#expect(model.isLoading)
		#expect(model.newStashMessage == "new")
		await gate.resumeCall(1)
	}

	@Test
	func resetDoesNotReuseADropConfirmationInANewRepository() async throws {
		let location = Location()
		let backend = Backend(value: snapshot())
		let model = makeModel(backend, location: location)
		defer { model.onDisappear() }
		model.didPresentStashDrop(stash(hash: "A"))
		model.reset()
		location.url = URL(fileURLWithPath: "/tmp/ReplacementRepository")
		model.didConfirmStashDrop()
		try await Task.sleep(for: .milliseconds(30))
		let urls = await backend.urls
		#expect(urls.isEmpty)
	}

	@Test
	func aPushWithNoEligibleChangesDoesNotDiscardItsMessage() async throws {
		let backend = Backend(value: snapshot(), outcome: .nothingToSave)
		let model = makeModel(backend)
		defer { model.onDisappear() }
		model.didChangeWorkingTreeState(hasChanges: true)
		model.includeUntrackedInStash = false
		model.newStashMessage = "important unsaved message"
		model.didRequestCreateStash()
		try await waitUntil { !model.isLoading }
		#expect(model.newStashMessage == "important unsaved message")
	}

	@Test
	func renumberingKeepsTheSelectedStashAndItsPreview() async throws {
		let backend = Backend(value: snapshot())
		let model = makeModel(backend)
		defer { model.onDisappear() }
		let selected = stash(hash: "A")
		model.apply(snapshot(stashes: [selected]))
		try await waitUntil { !model.isLoadingDiff }
		let fileID = model.selectedFileID

		model.apply(snapshot(stashes: [stash(hash: "B"), stash(hash: "A", reference: "stash@{1}")]))

		#expect(model.selectedStashID == selected.id)
		#expect(model.selectedStash?.reference == "stash@{1}")
		#expect(model.selectedFileID == fileID)
		let loaded = await backend.diffHashes
		#expect(loaded == ["A"])
	}

	@Test
	func aPushCapturesTheOptionsAtSubmissionTime() async throws {
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let backend = Backend(value: snapshot(), gate: gate)
		let model = makeModel(backend)
		defer { model.onDisappear() }
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "  submitted  "
		model.includeUntrackedInStash = true
		model.didRequestCreateStash()
		model.includeUntrackedInStash = false
		try await waitForCalls(1, in: gate)

		let messages = await backend.submittedMessages
		let options = await backend.submittedOptions
		#expect(messages == ["submitted"])
		#expect(options == [true])
		await gate.resumeCall(0)
		try await waitUntil { !model.isLoading }
		#expect(model.newStashMessage == "  submitted  ")
	}

	@Test
	func aPartialFailurePublishesItsSnapshotAndPreservesTheDraftForRetry() async throws {
		let backend = Backend(
			value: snapshot(stashes: [stash(hash: "saved")]),
			outcome: .failed("Some files could not be restored"))
		var snapshots: [RepositorySnapshot] = []
		var errors: [String] = []
		let model = makeModel(
			backend, didProduceSnapshot: { snapshots.append($0) }, didReceiveError: { errors.append($0) })
		defer { model.onDisappear() }
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "keep until successful"
		model.didRequestCreateStash()
		try await waitUntil { !model.isLoading }

		#expect(snapshots.first?.stashes.first?.hash == "saved")
		#expect(errors.count == 1)
		#expect(model.mutationMessage == errors.first)
		#expect(model.newStashMessage == "keep until successful")
		await backend.setResult(
			RepositoryStashMutationResult(outcome: .completed, snapshot: snapshot()))
		model.didRequestCreateStash()
		try await waitUntil { !model.isLoading }
		#expect(model.newStashMessage.isEmpty)
		#expect(model.mutationMessage == nil)
	}

	@Test
	func cancellingADropConfirmationByLeavingTheViewPreventsItsExecution() async throws {
		let backend = Backend(value: snapshot())
		let model = makeModel(backend)
		let selected = stash(hash: "A")
		model.apply(snapshot(stashes: [selected]))
		model.didPresentStashDrop(selected)
		model.onDisappear()
		model.didConfirmStashDrop()
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.pendingDrop == nil)
		let urls = await backend.urls
		#expect(urls.isEmpty)
	}

	@Test
	func aConfirmedDropRunsAgainstTheConfirmedRepository() async throws {
		let location = Location()
		let originalURL = location.url
		let backend = Backend(value: snapshot())
		let model = makeModel(backend, location: location)
		defer { model.onDisappear() }
		let selected = stash(hash: "A")
		model.apply(snapshot(stashes: [selected]))
		model.didPresentStashDrop(selected)
		model.didConfirmStashDrop()
		try await waitUntil { !model.isLoading }

		#expect(model.pendingDrop == nil)
		let urls = await backend.urls
		#expect(urls == [originalURL])
	}

	@Test
	func aDropConfirmedAfterTheRepositoryChangesIsRejected() async throws {
		let location = Location()
		let backend = Backend(value: snapshot())
		var errors: [String] = []
		let model = makeModel(backend, location: location, didReceiveError: { errors.append($0) })
		defer { model.onDisappear() }
		let selected = stash(hash: "A")
		model.apply(snapshot(stashes: [selected]))
		model.didPresentStashDrop(selected)
		location.url = URL(fileURLWithPath: "/tmp/ReplacementRepository")
		model.didConfirmStashDrop()
		try await Task.sleep(for: .milliseconds(30))

		#expect(model.pendingDrop == nil)
		#expect(errors.count == 1)
		let urls = await backend.urls
		#expect(urls.isEmpty)
	}

	@Test
	func observationTracksLoadingWithoutInvalidatingTheMessage() async {
		let model = makeModel(Backend(value: snapshot()))
		model.didChangeWorkingTreeState(hasChanges: true)
		model.newStashMessage = "kept"
		await confirmation("Loading becomes observable synchronously") { loadingChanged in
			await confirmation("Unrelated bookkeeping does not change the message", expectedCount: 0) {
				messageChanged in
				withObservationTracking {
					_ = model.isLoading
				} onChange: {
					loadingChanged()
				}
				withObservationTracking {
					_ = model.newStashMessage
				} onChange: {
					messageChanged()
				}
				model.didRequestCreateStash()
				model.onDisappear()
			}
		}
	}

	@Test
	func releasingTheModelDoesNotKeepAMutationAlive() async throws {
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let backend = Backend(value: snapshot(), gate: gate)
		var model: StashesViewModel? = makeModel(backend)
		weak var weakModel = model
		model?.didChangeWorkingTreeState(hasChanges: true)
		model?.didRequestCreateStash()
		try await waitForCalls(1, in: gate)

		model = nil

		#expect(weakModel == nil)
		await gate.resumeCall(0)
	}

	private func makeModel(
		_ backend: Backend, location: Location = Location(),
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in },
		didReceiveError: @escaping @MainActor (String) -> Void = { _ in }
	) -> StashesViewModel {
		StashesViewModel(
			dependencies: .init(
				useCase: backend, preferences: WorkspaceDiffPreferences(), repositoryURL: { location.url }),
			actions: .init(didProduceSnapshot: didProduceSnapshot, didReceiveError: didReceiveError))
	}
	private func stash(hash: String, reference: String = "stash@{0}", occurrence: Int = 0) -> GitStash
	{
		GitStash(reference: reference, hash: hash, subject: hash, date: nil, occurrence: occurrence)
	}
	private func snapshot(stashes: [GitStash] = []) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal, tags: [], stashes: stashes, fileTree: [])
	}
	private func waitUntil(_ condition: () -> Bool) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while !condition() {
			guard ContinuousClock.now < deadline else { throw CancellationError() }
			try await Task.sleep(for: .milliseconds(5))
		}
	}
	private func waitForCalls(_ count: Int, in gate: StashesUseCaseGate) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(5))
		while await gate.callCount() < count {
			guard ContinuousClock.now < deadline else { throw CancellationError() }
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
