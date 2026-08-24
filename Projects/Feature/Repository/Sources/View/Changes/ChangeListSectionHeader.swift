import DomainGitInterface
import SwiftUI

struct ChangeListSectionHeader: View {
	let title: String
	let count: Int

	var body: some View {
		HStack {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			Spacer(minLength: 8)
			Text(count, format: .number)
				.font(.caption.monospacedDigit())
				.foregroundStyle(.tertiary)
		}
		.textCase(nil)
	}
}
