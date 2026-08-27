import XCTest

@testable import FeatureRepository

@MainActor
final class RepositorySearchViewModelTests: XCTestCase {
	func testSearchCountsOccurrencesAndWrapsNextPrevious() async throws {
		let model = RepositorySearchViewModel()
		model.update(
			sources: [
				RepositorySearchSource(id: 1, text: "Tree tree"),
				RepositorySearchSource(id: 2, text: "another TREE"),
			]
		)
		model.query = "tree"
		try await waitUntil { model.matches.count == 3 }

		XCTAssertEqual(model.statusText, "1 of 3")
		XCTAssertEqual(model.currentMatch?.sourceID, 1)
		model.previous()
		XCTAssertEqual(model.statusText, "3 of 3")
		XCTAssertEqual(model.currentMatch?.sourceID, 2)
		model.next()
		XCTAssertEqual(model.statusText, "1 of 3")
	}

	func testSearchPreservesCurrentOccurrenceWhenSourcesAreRebuilt() async throws {
		let model = RepositorySearchViewModel()
		let sources = [RepositorySearchSource(id: 10, text: "one match and match")]
		model.update(sources: sources)
		model.query = "match"
		try await waitUntil { model.matches.count == 2 }
		model.next()
		let selectedMatch = model.currentMatch

		model.update(sources: sources + [RepositorySearchSource(id: 11, text: "match")])
		try await waitUntil { model.matches.count == 3 }

		XCTAssertEqual(model.currentMatch, selectedMatch)
		XCTAssertEqual(model.statusText, "2 of 3")
	}

	private func waitUntil(
		timeout: Duration = .seconds(1),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !condition() {
			if clock.now >= deadline {
				XCTFail("Condition timed out")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
