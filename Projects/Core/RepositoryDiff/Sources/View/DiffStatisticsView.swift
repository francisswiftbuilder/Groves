import DomainGitInterface
import SwiftUI

struct DiffStatisticsView: View {
	let document: DiffDocument

	var body: some View {
		HStack(spacing: 8) {
			Text("+\(document.additionCount)")
				.foregroundStyle(.green)
			Text("−\(document.deletionCount)")
				.foregroundStyle(.red)
		}
		.font(.caption.weight(.semibold).monospacedDigit())
		.accessibilityElement(children: .combine)
		.accessibilityLabel(
			"\(document.additionCount) additions, \(document.deletionCount) deletions"
		)
	}
}
