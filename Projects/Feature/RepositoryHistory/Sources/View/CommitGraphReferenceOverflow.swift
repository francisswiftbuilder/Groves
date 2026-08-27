import SwiftUI

struct CommitGraphReferenceOverflow: View {
	let count: Int

	var body: some View {
		Text("+\(count)")
			.font(.caption2.weight(.semibold))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(Color(nsColor: .quaternaryLabelColor).opacity(0.16), in: Capsule())
	}
}
