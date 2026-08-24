import DomainGitInterface
import SwiftUI

struct RemoteRow: View {
	let remote: GitRemote

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "icloud.fill")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.blue)
				.frame(width: 20)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(remote.name)
				Text(remote.fetchURL ?? remote.pushURL ?? "No URL")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}
