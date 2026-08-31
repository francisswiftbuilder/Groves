import XCTest

@testable import CoreRepositoryDiff

final class CommitDiffFileParserTests: XCTestCase {
	func testCommitDiffFileParserSeparatesChangedFiles() {
		let diff = """
			diff --git a/Sources/First.swift b/Sources/First.swift
			index 1111111..2222222 100644
			--- a/Sources/First.swift
			+++ b/Sources/First.swift
			@@ -1 +1 @@
			-old
			+new
			diff --git a/README.md b/README.md
			new file mode 100644
			--- /dev/null
			+++ b/README.md
			@@ -0,0 +1 @@
			+Read me
			"""

		let files = CommitDiffFileParser.parse(diff)

		XCTAssertEqual(files.map(\.path), ["Sources/First.swift", "README.md"])
		XCTAssertEqual(files.map(\.additions), [1, 1])
		XCTAssertEqual(files.map(\.deletions), [1, 0])
	}

	func testCancellableParserStopsWhenTaskIsCancelled() async {
		let section = """
			diff --git a/File.swift b/File.swift
			--- a/File.swift
			+++ b/File.swift
			@@ -1 +1 @@
			-old
			+new
			"""
		let diff = Array(repeating: section, count: 10_000).joined(separator: "\n")
		let task = Task.detached {
			try CommitDiffFileParser.parseCancellable(diff)
		}

		task.cancel()

		do {
			_ = try await task.value
			XCTFail("Cancelled diff parsing completed")
		} catch is CancellationError {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}
}
