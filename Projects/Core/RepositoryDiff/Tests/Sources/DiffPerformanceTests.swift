import XCTest

@testable import CoreRepositoryDiff

final class DiffPerformanceTests: XCTestCase {
	func testFiftyThousandLineDiffParseAndPairPerformance() {
		let diff = Self.diff(lineCount: 50_000)
		var documentLineCount = 0
		var rowCount = 0

		measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
			let document = DiffDocument(lines: DiffParser.parse(diff))
			let rows = DiffSideBySideBuilder.build(from: document)
			documentLineCount = document.lines.count
			rowCount = rows.count
		}

		XCTAssertEqual(documentLineCount, 50_001)
		XCTAssertEqual(rowCount, 50_000 - 50_000 / 3)
	}

	private static func diff(lineCount: Int) -> String {
		var lines = ["@@ -1,\(lineCount) +1,\(lineCount) @@"]
		lines.reserveCapacity(lineCount + 1)
		for index in 0..<lineCount {
			switch index % 3 {
			case 0: lines.append("+let added\(index) = \(index)")
			case 1: lines.append("-let removed\(index) = \(index)")
			default: lines.append(" let context\(index) = \(index)")
			}
		}
		return lines.joined(separator: "\n")
	}
}
