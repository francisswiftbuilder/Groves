import DomainGitInterface
import SwiftUI

struct CommitReferenceTag: View {
	let reference: String

	var body: some View {
		Text(reference)
			.font(.caption.weight(.medium))
			.foregroundStyle(referenceColor)
			.padding(.horizontal, 7)
			.padding(.vertical, 4)
			.background(referenceColor.opacity(0.12), in: Capsule())
	}

	private var referenceColor: Color {
		if reference.contains("HEAD") {
			return .primary
		}
		return reference.hasPrefix("origin/") ? .secondary : .blue
	}
}
