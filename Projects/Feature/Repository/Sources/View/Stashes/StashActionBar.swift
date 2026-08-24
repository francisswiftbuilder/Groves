import DomainGitInterface
import SwiftUI

struct StashActionBar: View {
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
