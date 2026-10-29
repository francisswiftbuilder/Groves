import Foundation
import Testing

@testable import CoreRepositoryDiff

struct CommitDiffFileParserTests {
	@Test
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

		#expect(files.map(\.path) == ["Sources/First.swift", "README.md"])
		#expect(files.map(\.additions) == [1, 1])
		#expect(files.map(\.deletions) == [1, 0])
	}

	@Test
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
			Issue.record("Cancelled diff parsing completed")
		} catch is CancellationError {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}
}
