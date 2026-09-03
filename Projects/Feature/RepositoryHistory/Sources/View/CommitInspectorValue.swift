import DomainGitInterface
import SwiftUI

struct CommitInspectorValue: View {
	let title: String
	let value: String
	let isMonospaced: Bool

	init(_ title: String, value: String, isMonospaced: Bool = false) {
		self.title = title
		self.value = value
		self.isMonospaced = isMonospaced
	}

	var body: some View {
		LabeledContent(title) {
			Text(value)
				.font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
				.multilineTextAlignment(.trailing)
				.textSelection(.enabled)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}
}
