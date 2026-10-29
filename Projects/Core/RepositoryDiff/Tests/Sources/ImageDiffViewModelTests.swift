import DomainGitInterface
import Foundation
import Testing

@testable import CoreRepositoryDiff

@MainActor
struct ImageDiffViewModelTests {
	@Test
	func testOnAppearLoadsBothImagesAndPublishesPresentation() async throws {
		let viewModel = ImageDiffViewModel(
			dependencies: .init { _ in
				return nil
			}
		)
		let diff = GitImageDiff(before: Data("before".utf8), after: Data("after".utf8))

		viewModel.onAppear(diff: diff)
		try await waitUntil {
			if case .loaded = viewModel.state { return true }
			return false
		}

		guard case .loaded(let presentation) = viewModel.state else {
			Issue.record("Expected loaded image presentation")
			return
		}
		#expect(presentation.beforeDecodingFailed)
		#expect(presentation.afterDecodingFailed)
	}

	@Test
	func testOnDisappearCancelsLoadingAndResetsTransientState() async {
		let viewModel = ImageDiffViewModel(
			dependencies: .init { _ in
				try? await Task.sleep(for: .seconds(1))
				return nil
			}
		)
		let diff = GitImageDiff(before: Data("before".utf8), after: Data("after".utf8))

		viewModel.onAppear(diff: diff)
		viewModel.onDisappear()

		guard case .idle = viewModel.state else {
			Issue.record("Expected idle state after disappearance")
			return
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
