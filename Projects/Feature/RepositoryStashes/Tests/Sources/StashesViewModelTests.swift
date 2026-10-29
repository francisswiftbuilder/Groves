import CoreRepositoryDiff
import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryStashes

@MainActor
struct StashesViewModelTests {
	@Test
	func testFirstSnapshotSelectsTheFirstStashAndLoadsItsDiff() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [stashes[0].id: textDiff(path: "README.md")]
			)
		)

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntil { viewModel.files.isEmpty == false }

		#expect(viewModel.selectedStashID == stashes[0].id)
		#expect(viewModel.files.map(\.path) == ["README.md"])
		#expect(viewModel.selectedFileID == viewModel.files.first?.id)
		#expect(!(viewModel.isLoadingDiff))
	}

	@Test
	func testSelectingAnotherStashReplacesTheDiffAndTheFileSelection() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				]
			)
		)

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntil { viewModel.files.map(\.path) == ["README.md"] }
		viewModel.didSelectStash(stashes[1].id)

		#expect(viewModel.files.isEmpty)
		#expect(viewModel.selectedFileID == nil)
		try await waitUntil { viewModel.files.map(\.path) == ["Sources/App.swift"] }
		#expect(viewModel.selectedStashID == stashes[1].id)
		#expect(viewModel.selectedFileID == viewModel.files.first?.id)
	}

	@Test
	func testSnapshotSelectionChangeLoadsTheNextStash() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				]
			)
		)

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntil { viewModel.files.map(\.path) == ["README.md"] }
		viewModel.apply(makeSnapshot(stashes: [stashes[1]]))

		#expect(viewModel.selectedStashID == stashes[1].id)
		try await waitUntil { viewModel.files.map(\.path) == ["Sources/App.swift"] }
	}

	@Test
	func testEmptyingTheStashListClearsEveryDiffState() async throws {
		let stash = makeStash(index: 0)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(diffs: [stash.id: textDiff(path: "README.md")])
		)

		viewModel.apply(makeSnapshot(stashes: [stash]))
		try await waitUntil { viewModel.files.isEmpty == false }
		viewModel.apply(makeSnapshot(stashes: []))

		#expect(viewModel.selectedStashID == nil)
		#expect(viewModel.selectedFileID == nil)
		#expect(viewModel.files.isEmpty)
		#expect(viewModel.diff == "")
		#expect(viewModel.imageDiff == nil)
		#expect(!(viewModel.isLoadingDiff))
		#expect(!(viewModel.isLoadingImageDiff))
	}

	@Test
	func testStaleStashDiffDoesNotReplaceTheNewerStashSelection() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				],
				gate: gate
			)
		)

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntilCallCount(1, in: gate)
		viewModel.didSelectStash(stashes[1].id)
		try await waitUntilCallCount(2, in: gate)
		await gate.resumeCall(1)
		try await waitUntil { viewModel.files.map(\.path) == ["Sources/App.swift"] }
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(viewModel.files.map(\.path) == ["Sources/App.swift"])
		#expect(viewModel.selectedStashID == stashes[1].id)
	}

	@Test
	func testStaleStashDiffDoesNotEndTheNewerLoadingState() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let viewModel = makeViewModel(useCase: StashesUseCaseStub(gate: gate))

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntilCallCount(1, in: gate)
		#expect(viewModel.isLoadingDiff)
		viewModel.didSelectStash(stashes[1].id)
		try await waitUntilCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(viewModel.isLoadingDiff)
		await gate.resumeCall(1)
	}

	@Test
	func testSelectingAnotherFileDiscardsTheStaleImageDiff() async throws {
		let stash = makeStash(index: 0)
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [stash.id: imageDiffText()],
				gate: gate
			)
		)

		viewModel.apply(makeSnapshot(stashes: [stash]))
		try await waitUntilCallCount(1, in: gate)
		await gate.resumeCall(0)
		try await waitUntil { viewModel.files.count == 2 }
		try await waitUntilCallCount(2, in: gate)
		let laterFileID = try #require(viewModel.files.last?.id)
		viewModel.didSelectFile(laterFileID)
		try await waitUntilCallCount(3, in: gate)
		await gate.resumeCall(1)
		try await Task.sleep(for: .milliseconds(150))

		#expect(viewModel.imageDiff == nil)
		#expect(viewModel.isLoadingImageDiff)
		await gate.resumeCall(2)
		try await waitUntil { viewModel.isLoadingImageDiff == false }
		#expect(viewModel.imageDiff?.after == Data("assets/after.png".utf8))
	}

	@Test
	func testResetClearsEveryStashSelectionAndDiffState() async throws {
		let stash = makeStash(index: 0)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(diffs: [stash.id: textDiff(path: "README.md")])
		)

		viewModel.apply(makeSnapshot(stashes: [stash]))
		try await waitUntil { viewModel.files.isEmpty == false }
		viewModel.reset()

		#expect(viewModel.stashes.isEmpty)
		#expect(viewModel.selectedStashID == nil)
		#expect(viewModel.selectedFileID == nil)
		#expect(viewModel.files.isEmpty)
		#expect(viewModel.diff == "")
		#expect(!(viewModel.isLoadingDiff))
		#expect(!(viewModel.isLoadingImageDiff))
	}

	private func makeViewModel(useCase: StashesUseCaseStub) -> StashesViewModel {
		StashesViewModel(
			dependencies: StashesViewModel.Dependencies(
				useCase: useCase,
				preferences: WorkspaceDiffPreferences(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: StashesViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in }
			)
		)
	}

	private func makeStash(index: Int) -> GitStash {
		GitStash(
			reference: "stash@{\(index)}",
			hash: "abc123\(index)",
			subject: "work in progress \(index)",
			date: nil
		)
	}

	private func textDiff(path: String) -> String {
		"""
		diff --git a/\(path) b/\(path)
		--- a/\(path)
		+++ b/\(path)
		@@ -1,1 +1,1 @@
		-before
		+after
		"""
	}

	private func imageDiffText() -> String {
		"""
		diff --git a/assets/before.png b/assets/before.png
		--- a/assets/before.png
		+++ b/assets/before.png
		@@ -1,1 +1,1 @@
		-before
		+after
		diff --git a/assets/after.png b/assets/after.png
		--- a/assets/after.png
		+++ b/assets/after.png
		@@ -1,1 +1,1 @@
		-before
		+after
		"""
	}

	private func makeSnapshot(stashes: [GitStash]) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [],
			amendChanges: [],
			commits: [],
			branches: [],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: stashes,
			fileTree: []
		)
	}

	private func waitUntilCallCount(
		_ count: Int,
		in gate: StashesUseCaseGate,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.callCount() < count {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for gated requests")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
