import DomainGitInterface
import SwiftUI

struct DiffStatisticsView: View {
	let diffLines: [DiffLine]

	var body: some View {
		HStack(spacing: 8) {
			Text("+\(additionCount)")
				.foregroundStyle(.green)
			Text("−\(deletionCount)")
				.foregroundStyle(.red)
		}
		.font(.caption.weight(.semibold).monospacedDigit())
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(additionCount) additions, \(deletionCount) deletions")
	}

	private var additionCount: Int {
		diffLines.count { $0.kind == .addition }
	}

	private var deletionCount: Int {
		diffLines.count { $0.kind == .deletion }
	}
}
