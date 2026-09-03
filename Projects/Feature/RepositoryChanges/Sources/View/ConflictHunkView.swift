import DomainGitInterface
import SwiftUI

struct ConflictHunkView: View {
	let hunk: GitConflictHunk
	let position: Int
	let count: Int
	let currentLabel: String
	let incomingLabel: String
	let filePath: String
	let searchText: String
	let isLoading: Bool
	let onResolve: (GitConflictHunkResolution) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Label("Conflict \(position) of \(count)", systemImage: "exclamationmark.triangle")
					.font(.subheadline.weight(.semibold))
				Spacer(minLength: 8)
			}

			ConflictSideBySideComparison(
				currentLabel: currentLabel,
				currentContent: hunk.current,
				incomingLabel: incomingLabel,
				incomingContent: hunk.incoming,
				filePath: filePath,
				searchText: searchText,
				currentUnavailableMessage: "File deleted",
				incomingUnavailableMessage: "File deleted"
			)

			if let base = hunk.base {
				DisclosureGroup("Base") {
					ConflictCodeSection(
						title: "Base",
						content: base,
						filePath: filePath,
						searchText: searchText,
						unavailableMessage: "Base unavailable"
					)
				}
			}

			ViewThatFits(in: .horizontal) {
				HStack(spacing: 8) {
					Spacer(minLength: 0)
					Button("Accept \(currentLabel)") { onResolve(.current) }
					Button("Accept \(incomingLabel)") { onResolve(.incoming) }
					Button("Accept Both") { onResolve(.both) }
						.buttonStyle(.borderedProminent)
				}

				HStack {
					Spacer(minLength: 0)
					Menu("Resolve Conflict") {
						Button("Accept \(currentLabel)") { onResolve(.current) }
						Button("Accept \(incomingLabel)") { onResolve(.incoming) }
						Button("Accept Both") { onResolve(.both) }
					}
				}
			}
			.controlSize(.small)
			.disabled(isLoading)
		}
		.padding(12)
		.background(.background.secondary)
		.clipShape(.rect(cornerRadius: 10))
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Conflict \(position) of \(count)")
	}
}

#Preview {
	ConflictHunkView(
		hunk: GitConflictHunk(
			index: 0,
			base: "let timeout = 15",
			current: "let timeout = 30",
			incoming: "let timeout = 60"
		),
		position: 1,
		count: 3,
		currentLabel: "Current",
		incomingLabel: "Incoming",
		filePath: "Sources/LoginView.swift",
		searchText: "",
		isLoading: false,
		onResolve: { _ in }
	)
	.frame(width: 620)
	.padding()
}
