import DomainGitInterface
import Foundation
import SwiftUI

struct CommitPlanProgressView: View {
	let progress: CommitAnalysisProgress?
	@State private var startedAt = Date()

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(phaseTitle).font(.callout)
			if let progress {
				ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
			} else {
				ProgressView().progressViewStyle(.linear)
			}
			HStack {
				if let progress { Text("\(progress.completed) / \(progress.total)").monospacedDigit() }
				Spacer()
				Text(startedAt, style: .timer).monospacedDigit()
					.accessibilityLabel("Time elapsed")
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var phaseTitle: String {
		guard let progress else { return "Reading staged changes…" }
		return progress.phase == .analyzing ? "Analyzing changes…" : "Grouping related changes…"
	}
}
