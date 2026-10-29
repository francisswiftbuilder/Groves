import Foundation
import Testing

@testable import CoreRepositoryDiff

struct DiffSideBySideBuilderTests {
	@Test
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
		let replacement = try #require(
			rows.first { $0.oldLine?.kind == .deletion || $0.newLine?.kind == .addition }
		)
		let contextRows = rows.filter { $0.oldLine?.kind == .context }

		#expect(replacement.oldLine?.sourceText == "old value")
		#expect(replacement.newLine?.sourceText == "new value")
		#expect(contextRows.count == 2)
		#expect(contextRows.first?.oldLine?.oldLineNumber == 1)
		#expect(contextRows.first?.newLine?.newLineNumber == 1)
	}

	@Test
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

		#expect(changedRows.count == 3)
		#expect(changedRows[0].oldLine == nil)
		#expect(changedRows[0].newLine?.sourceText == "let inserted = true")
		#expect(changedRows[1].oldLine?.sourceText == "let alpha = 1")
		#expect(changedRows[1].newLine?.sourceText == "let alpha = 10")
		#expect(changedRows[2].oldLine?.sourceText == "let beta = 2")
		#expect(changedRows[2].newLine?.sourceText == "let beta = 20")
	}

	@Test
	func testSideBySideBuilderDoesNotPairUnrelatedReplacement() {
		let diff = """
			@@ -1 +1 @@
			-completely unrelated old sentence
			+xyz
			"""

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		).filter { $0.fullWidthLine == nil }

		#expect(rows.count == 2)
		#expect(rows.count { $0.oldLine != nil } == 1)
		#expect(rows.count { $0.newLine != nil } == 1)
	}

	@Test
	func testSideBySideBuilderFallsBackToIndexPairingForLargeBlock() {
		let deletions = (1...65).map { "-old \($0)" }.joined(separator: "\n")
		let additions = (1...65).map { "+new \($0)" }.joined(separator: "\n")
		let diff = "@@ -1,65 +1,65 @@\n\(deletions)\n\(additions)"

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		).filter { $0.fullWidthLine == nil }

		#expect(rows.count == 65)
		#expect(rows.allSatisfy { $0.oldLine != nil && $0.newLine != nil })
	}

	@Test
	func testFiftyThousandLineDiffProducesExpectedRows() {
		let content = (1...50_000).map { " line \($0)" }.joined(separator: "\n")
		let diff = "@@ -1,50000 +1,50000 @@\n\(content)"

		let rows = DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		)

		#expect(rows.count == 50_001)
	}

	@Test
	func testCancellableBuilderStopsWhenTaskIsCancelled() async {
		let diff = "@@ -1 +1 @@\n-old\n+new"
		let document = DiffDocument(lines: DiffParser.parse(diff))
		let task = Task.detached {
			try DiffSideBySideBuilder.buildCancellable(from: document)
		}

		task.cancel()

		do {
			_ = try await task.value
			Issue.record("Expected cancellation")
		} catch is CancellationError {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}
}
