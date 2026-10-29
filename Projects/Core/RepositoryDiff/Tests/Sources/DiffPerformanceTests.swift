import Darwin
import Foundation
import Testing

@testable import CoreRepositoryDiff

struct DiffPerformanceTests {
	@Test
	func testFiftyThousandLineDiffParseAndPairPerformance() {
		let diff = Self.diff(lineCount: 50_000)
		var measurements = ["iteration,wall_nanoseconds,thread_cpu_nanoseconds"]
		for iteration in 0..<10 {
			let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
			let start = ContinuousClock.now
			let counts = autoreleasepool {
				let document = DiffDocument(lines: DiffParser.parse(diff))
				let rows = DiffSideBySideBuilder.build(from: document)
				return (lines: document.lines.count, rows: rows.count)
			}
			let elapsed = start.duration(to: .now).components
			let wallNanoseconds =
				Double(elapsed.seconds) * 1_000_000_000
				+ Double(elapsed.attoseconds) / 1_000_000_000
			let cpuNanoseconds = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart
			measurements.append("\(iteration),\(wallNanoseconds),\(cpuNanoseconds)")
			#expect(counts.lines == 50_001)
			#expect(counts.rows == 50_000 - 50_000 / 3)
		}
		Attachment.record(measurements.joined(separator: "\n"), named: "diff-performance.csv")
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
