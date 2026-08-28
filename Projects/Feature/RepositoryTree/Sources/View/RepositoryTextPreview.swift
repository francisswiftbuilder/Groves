import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTextPreview: View {
	let content: String

	var body: some View {
		RepositoryFindableTextView(content: content)
			.background(
				Color(nsColor: .controlBackgroundColor),
				in: RoundedRectangle(cornerRadius: 12, style: .continuous)
			)
			.overlay {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
			}
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.padding(16)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}
