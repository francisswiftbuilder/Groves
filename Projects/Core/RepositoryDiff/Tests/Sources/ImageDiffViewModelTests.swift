import AppKit
import DomainGitInterface
import Foundation
import Testing

@testable import CoreRepositoryDiff

@MainActor
struct ImageDiffViewModelTests {
	@Test
	func testUpdateLoadsBothImagesAndPublishesPresentation() async {
		let viewModel = ImageDiffViewModel(
			dependencies: .init { _ in
				return nil
			}
		)
		let diff = GitImageDiff(before: Data("before".utf8), after: Data("after".utf8))

		await viewModel.update(diff: diff)

		guard case .loaded(let presentation) = viewModel.state else {
			Issue.record("Expected loaded image presentation")
			return
		}
		#expect(presentation.beforeDecodingFailed)
		#expect(presentation.afterDecodingFailed)
	}

	@Test
	func testStaleResultDoesNotOverwriteLatestPresentation() async throws {
		let staleData = Data("stale".utf8)
		let gate = DecodeGate()
		let viewModel = ImageDiffViewModel(
			dependencies: .init { data in
				guard data == staleData else {
					return NSImage(size: NSSize(width: 1, height: 1))
				}
				await gate.wait()
				return nil
			}
		)
		let staleDiff = GitImageDiff(before: staleData, after: nil)
		let latestDiff = GitImageDiff(before: Data("latest".utf8), after: nil)

		let staleTask = Task { await viewModel.update(diff: staleDiff) }
		try await waitUntil {
			if case .loading = viewModel.state { return true }
			return false
		}
		await viewModel.update(diff: latestDiff)
		gate.open()
		await staleTask.value

		guard case .loaded(let presentation) = viewModel.state else {
			Issue.record("Expected loaded image presentation")
			return
		}
		#expect(presentation.beforeImage != nil)
		#expect(!presentation.beforeDecodingFailed)
	}

	@Test
	func testCancelledUpdateResetsToIdleAndReloadPublishesPresentation() async throws {
		let gate = DecodeGate()
		let recorder = DecodeRecorder()
		let viewModel = ImageDiffViewModel(
			dependencies: .init { _ in
				recorder.count += 1
				await gate.wait()
				return NSImage(size: NSSize(width: 1, height: 1))
			}
		)
		let diff = GitImageDiff(before: Data("before".utf8), after: Data("after".utf8))

		let task = Task { await viewModel.update(diff: diff) }
		try await waitUntil {
			if case .loading = viewModel.state { return true }
			return false
		}
		task.cancel()
		gate.open()
		await task.value

		guard case .idle = viewModel.state else {
			Issue.record("Expected idle state after cancellation")
			return
		}

		await viewModel.update(diff: diff)

		guard case .loaded(let presentation) = viewModel.state else {
			Issue.record("Expected loaded image presentation after reload")
			return
		}
		#expect(presentation.beforeImage != nil)
		#expect(presentation.afterImage != nil)
		#expect(recorder.count == 4)
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

	@MainActor
	private final class DecodeGate {
		private var isOpen = false
		private var continuations: [CheckedContinuation<Void, Never>] = []

		func wait() async {
			guard !isOpen else { return }
			await withCheckedContinuation { continuations.append($0) }
		}

		func open() {
			isOpen = true
			let pending = continuations
			continuations = []
			for continuation in pending {
				continuation.resume()
			}
		}
	}

	@MainActor
	private final class DecodeRecorder {
		var count = 0
	}
}
