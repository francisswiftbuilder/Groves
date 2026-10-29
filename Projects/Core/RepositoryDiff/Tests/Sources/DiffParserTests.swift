import DomainGitInterface
import Foundation
import Testing

@testable import CoreRepositoryDiff

struct DiffParserTests {
	@Test
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
		let deletion = try #require(lines.first { $0.kind == .deletion })
		let addition = try #require(lines.first { $0.kind == .addition })

		#expect(deletion.oldLineNumber == 2)
		#expect(deletion.newLineNumber == nil)
		#expect(addition.oldLineNumber == nil)
		#expect(addition.newLineNumber == 2)
		#expect(deletion.selection == GitDiffLineSelection(oldLineNumber: 2, newLineNumber: 2))
		#expect(addition.selection == deletion.selection)
		#expect(deletion.showsAction)
		#expect(!(addition.showsAction))
	}

	@Test
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

		#expect(lines.filter { $0.kind == .deletion }.count == 1)
		#expect(lines.filter { $0.kind == .addition }.count == 1)
	}

	@Test
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

		#expect(lines.map(\.kind) == [.deletion, .addition, .context])
		#expect(lines.map(\.sourceText) == ["old", "new", "context"])
	}

	@Test
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
		let hunk = try #require(lines.first { $0.kind == .hunk })
		let deletion = try #require(lines.first { $0.kind == .deletion })
		let addition = try #require(lines.first { $0.kind == .addition })

		#expect(hunk.hunkSelection == GitDiffHunkSelection(oldStartLine: 40, newStartLine: 40))
		#expect(deletion.changedRange == DiffTextRange(location: 14, length: 1))
		#expect(addition.changedRange == DiffTextRange(location: 14, length: 1))
	}
}
