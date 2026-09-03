import XCTest

@testable import CoreRepositoryDiff

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

	func testTenThousandLineSearchStartsWithinMainActorBudget() async throws {
		let model = RepositorySearchViewModel()
		let sources = (0..<10_000).map {
			RepositorySearchSource(id: $0, text: "line \($0) contains needle")
		}
		model.update(sources: sources)
		let clock = ContinuousClock()
		let start = clock.now

		model.query = "needle"

		let elapsed = start.duration(to: clock.now)
		XCTAssertLessThan(elapsed, .milliseconds(100))
		try await waitUntil(timeout: .seconds(2)) { model.matches.count == sources.count }
	}

	func testRunningSearchDoesNotRetainViewModel() {
		weak var weakModel: RepositorySearchViewModel?
		autoreleasepool {
			let model = RepositorySearchViewModel()
			model.update(
				sources: (0..<10_000).map {
					RepositorySearchSource(id: $0, text: "searchable line \($0)")
				}
			)
			model.query = "missing"
			weakModel = model
		}

		XCTAssertNil(weakModel)
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
