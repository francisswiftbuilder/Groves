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
}
