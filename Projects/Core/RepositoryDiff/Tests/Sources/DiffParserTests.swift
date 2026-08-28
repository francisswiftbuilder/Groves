import DomainGitInterface
import XCTest

@testable import CoreRepositoryDiff

final class DiffParserTests: XCTestCase {
	func testDiffParserPairsReplacementLinesWithSourceCoordinates() throws {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1,4 +1,4 @@
			 one
			-two
			+TWO
			 three
			"""

		let lines = DiffParser.parse(diff)
		let deletion = try XCTUnwrap(lines.first { $0.kind == .deletion })
		let addition = try XCTUnwrap(lines.first { $0.kind == .addition })

		XCTAssertEqual(deletion.oldLineNumber, 2)
		XCTAssertNil(deletion.newLineNumber)
		XCTAssertNil(addition.oldLineNumber)
		XCTAssertEqual(addition.newLineNumber, 2)
		XCTAssertEqual(
			deletion.selection,
			GitDiffLineSelection(oldLineNumber: 2, newLineNumber: 2)
		)
		XCTAssertEqual(addition.selection, deletion.selection)
		XCTAssertTrue(deletion.showsAction)
		XCTAssertFalse(addition.showsAction)
	}

	func testDiffParserTreatsTriplePrefixInsideHunkAsChangedContent() {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1 +1 @@
			---old
			+++new
			"""

		let lines = DiffParser.parse(diff)

		XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 1)
		XCTAssertEqual(lines.filter { $0.kind == .addition }.count, 1)
	}

	func testDiffParserReturnsOnlySourceLinesForPresentation() {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			index 1111111..2222222 100644
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1,2 +1,2 @@
			-old
			+new
			 context
			"""

		let lines = DiffParser.parseSourceLines(diff)

		XCTAssertEqual(lines.map(\.kind), [.deletion, .addition, .context])
		XCTAssertEqual(lines.map(\.sourceText), ["old", "new", "context"])
	}

	func testDiffParserPreservesHunkSelectionAndIntraLineRanges() throws {
		let diff = """
			diff --git a/App.swift b/App.swift
			--- a/App.swift
			+++ b/App.swift
			@@ -40,2 +40,2 @@
			-let timeout = 30
			+let timeout = 60
			 context
			"""

		let lines = DiffParser.parse(diff)
		let hunk = try XCTUnwrap(lines.first { $0.kind == .hunk })
		let deletion = try XCTUnwrap(lines.first { $0.kind == .deletion })
		let addition = try XCTUnwrap(lines.first { $0.kind == .addition })

		XCTAssertEqual(
			hunk.hunkSelection,
			GitDiffHunkSelection(oldStartLine: 40, newStartLine: 40)
		)
		XCTAssertEqual(deletion.changedRange, DiffTextRange(location: 14, length: 1))
		XCTAssertEqual(addition.changedRange, DiffTextRange(location: 14, length: 1))
	}
}
