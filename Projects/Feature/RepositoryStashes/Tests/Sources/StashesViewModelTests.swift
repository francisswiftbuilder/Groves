import CoreRepositoryDiff
import DomainGitInterface
import XCTest

@testable import FeatureRepositoryStashes

@MainActor
final class StashesViewModelTests: XCTestCase {
	func testFirstSnapshotSelectsTheFirstStashAndLoadsItsDiff() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(
				diffs: [stashes[0].id: textDiff(path: "README.md")]
			)
		)

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntil { viewModel.files.isEmpty == false }

		XCTAssertEqual(viewModel.selectedStashID, stashes[0].id)
		XCTAssertEqual(viewModel.files.map(\.path), ["README.md"])
		XCTAssertEqual(viewModel.selectedFileID, viewModel.files.first?.id)
		XCTAssertFalse(viewModel.isLoadingDiff)
	}

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

		XCTAssertTrue(viewModel.files.isEmpty)
		XCTAssertNil(viewModel.selectedFileID)
		try await waitUntil { viewModel.files.map(\.path) == ["Sources/App.swift"] }
		XCTAssertEqual(viewModel.selectedStashID, stashes[1].id)
		XCTAssertEqual(viewModel.selectedFileID, viewModel.files.first?.id)
	}

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

		XCTAssertEqual(viewModel.selectedStashID, stashes[1].id)
		try await waitUntil { viewModel.files.map(\.path) == ["Sources/App.swift"] }
	}

	func testEmptyingTheStashListClearsEveryDiffState() async throws {
		let stash = makeStash(index: 0)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(diffs: [stash.id: textDiff(path: "README.md")])
		)

		viewModel.apply(makeSnapshot(stashes: [stash]))
		try await waitUntil { viewModel.files.isEmpty == false }
		viewModel.apply(makeSnapshot(stashes: []))

		XCTAssertNil(viewModel.selectedStashID)
		XCTAssertNil(viewModel.selectedFileID)
		XCTAssertTrue(viewModel.files.isEmpty)
		XCTAssertEqual(viewModel.diff, "")
		XCTAssertNil(viewModel.imageDiff)
		XCTAssertFalse(viewModel.isLoadingDiff)
		XCTAssertFalse(viewModel.isLoadingImageDiff)
	}

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

		XCTAssertEqual(viewModel.files.map(\.path), ["Sources/App.swift"])
		XCTAssertEqual(viewModel.selectedStashID, stashes[1].id)
	}

	func testStaleStashDiffDoesNotEndTheNewerLoadingState() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let gate = StashesUseCaseGate(suspendsRequests: true)
		let viewModel = makeViewModel(useCase: StashesUseCaseStub(gate: gate))

		viewModel.apply(makeSnapshot(stashes: stashes))
		try await waitUntilCallCount(1, in: gate)
		XCTAssertTrue(viewModel.isLoadingDiff)
		viewModel.didSelectStash(stashes[1].id)
		try await waitUntilCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(viewModel.isLoadingDiff)
		await gate.resumeCall(1)
	}

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
		let laterFileID = try XCTUnwrap(viewModel.files.last?.id)
		viewModel.didSelectFile(laterFileID)
		try await waitUntilCallCount(3, in: gate)
		await gate.resumeCall(1)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertNil(viewModel.imageDiff)
		XCTAssertTrue(viewModel.isLoadingImageDiff)
		await gate.resumeCall(2)
		try await waitUntil { viewModel.isLoadingImageDiff == false }
		XCTAssertEqual(viewModel.imageDiff?.after, Data("assets/after.png".utf8))
	}

	func testResetClearsEveryStashSelectionAndDiffState() async throws {
		let stash = makeStash(index: 0)
		let viewModel = makeViewModel(
			useCase: StashesUseCaseStub(diffs: [stash.id: textDiff(path: "README.md")])
		)

		viewModel.apply(makeSnapshot(stashes: [stash]))
		try await waitUntil { viewModel.files.isEmpty == false }
		viewModel.reset()

		XCTAssertTrue(viewModel.stashes.isEmpty)
		XCTAssertNil(viewModel.selectedStashID)
		XCTAssertNil(viewModel.selectedFileID)
		XCTAssertTrue(viewModel.files.isEmpty)
		XCTAssertEqual(viewModel.diff, "")
		XCTAssertFalse(viewModel.isLoadingDiff)
		XCTAssertFalse(viewModel.isLoadingImageDiff)
	}

	private func makeViewModel(useCase: StashesUseCaseStub) -> StashesViewModel {
		StashesViewModel(
			dependencies: StashesViewModelDependencies(
				useCase: useCase,
				preferences: WorkspaceDiffPreferences(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: StashesViewModelActions(
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
				XCTFail("Timed out waiting for gated requests")
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
				XCTFail("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
