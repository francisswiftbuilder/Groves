import DomainGitInterface
import Foundation
import XCTest

@testable import CoreRepositoryDiff

@MainActor
final class ImageDiffViewModelTests: XCTestCase {
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
			return XCTFail("Expected loaded image presentation")
		}
		XCTAssertTrue(presentation.beforeDecodingFailed)
		XCTAssertTrue(presentation.afterDecodingFailed)
	}

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

		if case .idle = viewModel.state {
			XCTAssertTrue(true)
		} else {
			XCTFail("Expected idle state after disappearance")
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
