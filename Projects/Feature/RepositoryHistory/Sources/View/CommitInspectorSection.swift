import DomainGitInterface
import SwiftUI

struct CommitInspectorSection<Content: View>: View {
	let title: String
	@ViewBuilder let content: () -> Content

	init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
		self.title = title
		self.content = content
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.subheadline.weight(.semibold))
			content()
		}
	}
}
