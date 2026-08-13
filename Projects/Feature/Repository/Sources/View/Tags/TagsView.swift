import DomainGitInterface
import SwiftUI

struct TagsView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.tags.isEmpty {
				EmptyStateView(
					title: "No Tags",
					message: "Create a tag to mark an important revision.",
					systemImage: "tag"
				)
			} else {
				List(selection: $viewModel.selectedTagID) {
					ForEach(viewModel.tags) { tag in
						TagRow(tag: tag)
							.tag(tag.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Tags")
		.navigationSubtitle("\(viewModel.tags.count) tags")
		.safeAreaInset(edge: .bottom) {
			TagActionBar(viewModel: viewModel)
		}
	}
}

private struct TagRow: View {
	let tag: GitTag

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "tag.fill")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.orange)
				.frame(width: 20)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 3) {
				Text(tag.name)
				HStack(spacing: 8) {
					Text(tag.shortHash)
						.font(.system(.caption, design: .monospaced))
					if !tag.subject.isEmpty {
						Text(tag.subject)
							.lineLimit(1)
					}
					if let date = tag.date {
						Text(date, style: .date)
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

private struct TagActionBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		HStack(spacing: 10) {
			Label("New Tag", systemImage: "tag")
				.font(.callout)
				.foregroundStyle(.secondary)
			TextField("Tag name", text: $viewModel.newTagName)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: 180)
			TextField("Annotation message", text: $viewModel.newTagMessage)
				.textFieldStyle(.roundedBorder)
			Button("Create") {
				viewModel.didRequestCreateTag()
			}
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			Button("Delete", role: .destructive) {
				viewModel.didRequestDeleteTag()
			}
			.disabled(viewModel.selectedTag == nil)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
