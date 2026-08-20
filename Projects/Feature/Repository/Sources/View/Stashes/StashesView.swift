import DomainGitInterface
import SwiftUI

struct StashesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.stashes.isEmpty {
				EmptyStateView(
					title: "No Stashes",
					message: "Save uncommitted changes to return to them later.",
					systemImage: "archivebox"
				)
			} else {
				List(selection: $viewModel.selectedStashID) {
					ForEach(viewModel.stashes) { stash in
						StashRow(stash: stash)
							.tag(stash.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Stashes")
		.navigationSubtitle("\(viewModel.stashes.count) stashes")
		.safeAreaInset(edge: .bottom) {
			StashActionBar(viewModel: viewModel)
		}
	}
}

private struct StashRow: View {
	let stash: GitStash

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "archivebox.fill")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.purple)
				.frame(width: 20)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(stash.subject)
					.lineLimit(1)

				HStack(spacing: 8) {
					Text(stash.reference)
					Text(stash.hash.prefix(7))
						.font(.system(.caption, design: .monospaced))
					if let date = stash.date {
						Text(date, style: .relative)
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}

private struct StashActionBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		HStack(spacing: 10) {
			Label("New Stash", systemImage: "archivebox")
				.font(.callout)
				.foregroundStyle(.secondary)

			TextField("Message (optional)", text: $viewModel.newStashMessage)
				.textFieldStyle(.roundedBorder)
				.onSubmit {
					viewModel.didRequestCreateStash()
				}

			Button("Stash") {
				viewModel.didRequestCreateStash()
			}
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.changes.isEmpty || viewModel.isLoading)

			Button("Apply") {
				viewModel.didRequestApplyStash()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)

			Button("Pop") {
				viewModel.didRequestPopStash()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)

			Button("Delete", role: .destructive) {
				viewModel.didRequestDropStash()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
