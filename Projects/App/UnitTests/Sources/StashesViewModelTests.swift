import CoreRepositoryDiff
import DomainGitInterface
import XCTest

@testable import FeatureRepositoryStashes
@testable import Trees

@MainActor
final class StashesViewModelTests: XCTestCase {
	func testFirstSnapshotSelectsTheFirstStashAndLoadsItsDiff() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: stashes,
				stashDiffs: [stashes[0].id: textDiff(path: "README.md")]
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))

		try await waitUntil { stashesViewModel.files.isEmpty == false }

		XCTAssertEqual(stashesViewModel.selectedStashID, stashes[0].id)
		XCTAssertEqual(stashesViewModel.files.map(\.path), ["README.md"])
		XCTAssertEqual(stashesViewModel.selectedFileID, stashesViewModel.files.first?.id)
		XCTAssertFalse(stashesViewModel.isLoadingDiff)
	}

	func testSelectingAnotherStashReplacesTheDiffAndTheFileSelection() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: stashes,
				stashDiffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				]
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { stashesViewModel.files.map(\.path) == ["README.md"] }

		stashesViewModel.didSelectStash(stashes[1].id)

		XCTAssertTrue(stashesViewModel.files.isEmpty)
		XCTAssertNil(stashesViewModel.selectedFileID)

		try await waitUntil { stashesViewModel.files.map(\.path) == ["Sources/App.swift"] }

		XCTAssertEqual(stashesViewModel.selectedStashID, stashes[1].id)
		XCTAssertEqual(stashesViewModel.selectedFileID, stashesViewModel.files.first?.id)
	}

	func testDroppingTheSelectedStashSelectsTheNextStashAndReloadsItsDiff() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: stashes,
				stashDiffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				]
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { stashesViewModel.files.map(\.path) == ["README.md"] }

		workspace.viewModel.didProduceSnapshot(makeSnapshot(stashes: [stashes[1]]))

		XCTAssertEqual(stashesViewModel.selectedStashID, stashes[1].id)

		try await waitUntil { stashesViewModel.files.map(\.path) == ["Sources/App.swift"] }
	}

	func testEmptyingTheStashListClearsEveryDiffState() async throws {
		let stash = makeStash(index: 0)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: [stash],
				stashDiffs: [stash.id: textDiff(path: "README.md")]
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { stashesViewModel.files.isEmpty == false }

		workspace.viewModel.didProduceSnapshot(makeSnapshot(stashes: []))

		XCTAssertNil(stashesViewModel.selectedStashID)
		XCTAssertNil(stashesViewModel.selectedFileID)
		XCTAssertTrue(stashesViewModel.files.isEmpty)
		XCTAssertEqual(stashesViewModel.diff, "")
		XCTAssertNil(stashesViewModel.imageDiff)
		XCTAssertFalse(stashesViewModel.isLoadingDiff)
		XCTAssertFalse(stashesViewModel.isLoadingImageDiff)
	}

	func testStaleStashDiffDoesNotReplaceTheNewerStashSelection() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: stashes,
				stashDiffs: [
					stashes[0].id: textDiff(path: "README.md"),
					stashes[1].id: textDiff(path: "Sources/App.swift"),
				],
				diffGate: gate
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilTotalCallCount(1, in: gate)

		stashesViewModel.didSelectStash(stashes[1].id)
		try await waitUntilTotalCallCount(2, in: gate)

		await gate.resumeCall(1)
		try await waitUntil { stashesViewModel.files.map(\.path) == ["Sources/App.swift"] }

		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertEqual(stashesViewModel.files.map(\.path), ["Sources/App.swift"])
		XCTAssertEqual(stashesViewModel.selectedStashID, stashes[1].id)
	}

	func testStaleStashDiffDoesNotEndTheNewerLoadingState() async throws {
		let stashes = [makeStash(index: 0), makeStash(index: 1)]
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(stashes: stashes, diffGate: gate)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilTotalCallCount(1, in: gate)
		XCTAssertTrue(stashesViewModel.isLoadingDiff)

		stashesViewModel.didSelectStash(stashes[1].id)
		try await waitUntilTotalCallCount(2, in: gate)

		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(
			stashesViewModel.isLoadingDiff,
			"A stale stash diff must not end the newer request's loading state"
		)
	}

	func testSelectingAnotherFileDiscardsTheStaleImageDiff() async throws {
		let stash = makeStash(index: 0)
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: [stash],
				stashDiffs: [stash.id: imageDiffText()],
				diffGate: gate
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilTotalCallCount(1, in: gate)

		await gate.resumeCall(0)
		try await waitUntil { stashesViewModel.files.count == 2 }
		try await waitUntilTotalCallCount(2, in: gate)

		let laterFileID = try XCTUnwrap(stashesViewModel.files.last?.id)
		stashesViewModel.didSelectFile(laterFileID)
		try await waitUntilTotalCallCount(3, in: gate)

		await gate.resumeCall(1)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertNil(
			stashesViewModel.imageDiff,
			"A stale image diff must not be published for the newer file"
		)
		XCTAssertTrue(
			stashesViewModel.isLoadingImageDiff,
			"A stale image diff must not end the newer request's loading state"
		)

		await gate.resumeCall(2)
		try await waitUntil { stashesViewModel.isLoadingImageDiff == false }

		XCTAssertEqual(stashesViewModel.imageDiff?.after, Data("assets/after.png".utf8))
	}

	func testResetClearsEveryStashSelectionAndDiffState() async throws {
		let stash = makeStash(index: 0)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				stashes: [stash],
				stashDiffs: [stash.id: textDiff(path: "README.md")]
			)
		)
		let stashesViewModel = workspace.stashesViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { stashesViewModel.files.isEmpty == false }

		stashesViewModel.reset()

		XCTAssertTrue(stashesViewModel.stashes.isEmpty)
		XCTAssertNil(stashesViewModel.selectedStashID)
		XCTAssertNil(stashesViewModel.selectedFileID)
		XCTAssertTrue(stashesViewModel.files.isEmpty)
		XCTAssertEqual(stashesViewModel.diff, "")
		XCTAssertFalse(stashesViewModel.isLoadingDiff)
		XCTAssertFalse(stashesViewModel.isLoadingImageDiff)
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

	private func waitUntilTotalCallCount(
		_ count: Int,
		in gate: GitDiffGate,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.totalCallCount() < count {
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
