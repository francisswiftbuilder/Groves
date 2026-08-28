import SwiftUI

struct CommitDiffStatistics: View {
	let file: CommitDiffFile

	var body: some View {
		HStack(spacing: 8) {
			Text("+\(file.additions)")
				.foregroundStyle(.green)
			Text("−\(file.deletions)")
				.foregroundStyle(.red)
		}
		.font(.caption.weight(.semibold).monospacedDigit())
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(file.additions) additions, \(file.deletions) deletions")
	}
}
