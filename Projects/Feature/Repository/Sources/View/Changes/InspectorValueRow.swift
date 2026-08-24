import DomainGitInterface
import Foundation
import SwiftUI

struct InspectorValueRow: View {
	let title: String
	let value: String

	init(_ title: String, value: String) {
		self.title = title
		self.value = value
	}

	var body: some View {
		LabeledContent(title) {
			Text(value)
				.multilineTextAlignment(.trailing)
				.textSelection(.enabled)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}
}
