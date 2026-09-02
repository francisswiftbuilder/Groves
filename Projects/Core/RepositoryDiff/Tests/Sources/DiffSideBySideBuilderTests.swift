import XCTest

@testable import CoreRepositoryDiff

final class DiffSideBySideBuilderTests: XCTestCase {
	func testSideBySideBuilderAlignsReplacementAndContextLines() throws {
		let diff = """
			@@ -1,3 +1,3 @@
			 unchanged
			-old value
			+new value
			 trailing
			"""

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		)
		let replacement = try XCTUnwrap(
			rows.first { $0.oldLine?.kind == .deletion || $0.newLine?.kind == .addition }
		)
		let contextRows = rows.filter { $0.oldLine?.kind == .context }

		XCTAssertEqual(replacement.oldLine?.sourceText, "old value")
		XCTAssertEqual(replacement.newLine?.sourceText, "new value")
		XCTAssertEqual(contextRows.count, 2)
		XCTAssertEqual(contextRows.first?.oldLine?.oldLineNumber, 1)
		XCTAssertEqual(contextRows.first?.newLine?.newLineNumber, 1)
	}

	func testSideBySideBuilderAlignsShiftedInsertionBySimilarity() {
		let diff = """
			@@ -1,2 +1,3 @@
			-let alpha = 1
			-let beta = 2
			+let inserted = true
			+let alpha = 10
			+let beta = 20
			"""

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		)
		let changedRows = rows.filter { $0.fullWidthLine == nil }

		XCTAssertEqual(changedRows.count, 3)
		XCTAssertNil(changedRows[0].oldLine)
		XCTAssertEqual(changedRows[0].newLine?.sourceText, "let inserted = true")
		XCTAssertEqual(changedRows[1].oldLine?.sourceText, "let alpha = 1")
		XCTAssertEqual(changedRows[1].newLine?.sourceText, "let alpha = 10")
		XCTAssertEqual(changedRows[2].oldLine?.sourceText, "let beta = 2")
		XCTAssertEqual(changedRows[2].newLine?.sourceText, "let beta = 20")
	}

	func testSideBySideBuilderDoesNotPairUnrelatedReplacement() {
		let diff = """
			@@ -1 +1 @@
			-completely unrelated old sentence
			+xyz
			"""

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		).filter { $0.fullWidthLine == nil }

		XCTAssertEqual(rows.count, 2)
		XCTAssertEqual(rows.count { $0.oldLine != nil }, 1)
		XCTAssertEqual(rows.count { $0.newLine != nil }, 1)
	}

	func testSideBySideBuilderFallsBackToIndexPairingForLargeBlock() {
		let deletions = (1...65).map { "-old \($0)" }.joined(separator: "\n")
		let additions = (1...65).map { "+new \($0)" }.joined(separator: "\n")
		let diff = "@@ -1,65 +1,65 @@\n\(deletions)\n\(additions)"

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		).filter { $0.fullWidthLine == nil }

		XCTAssertEqual(rows.count, 65)
		XCTAssertTrue(rows.allSatisfy { $0.oldLine != nil && $0.newLine != nil })
	}

	func testFiftyThousandLineDiffProducesExpectedRows() {
		let content = (1...50_000).map { " line \($0)" }.joined(separator: "\n")
		let diff = "@@ -1,50000 +1,50000 @@\n\(content)"

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		)

		XCTAssertEqual(rows.count, 50_001)
	}

	func testCancellableBuilderStopsWhenTaskIsCancelled() async {
		let diff = "@@ -1 +1 @@\n-old\n+new"
		let document = DiffDocument(lines: DiffParser.parse(diff))
		let task = Task.detached {
			try DiffSideBySideBuilder.buildCancellable(from: document)
		}

		task.cancel()

		do {
			_ = try await task.value
			XCTFail("Expected cancellation")
		} catch is CancellationError {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}
}
