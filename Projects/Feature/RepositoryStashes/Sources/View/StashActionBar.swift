import DomainGitInterface
import SwiftUI

struct StashActionBar: View {
	@Bindable var viewModel: StashesViewModel
	let onDelete: () -> Void

	init(viewModel: StashesViewModel, onDelete: @escaping () -> Void) {
		self.viewModel = viewModel
		self.onDelete = onDelete
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextField("Stash message (optional)", text: $viewModel.newStashMessage)
				.textFieldStyle(.roundedBorder)
				.onSubmit { viewModel.didRequestCreateStash() }
			HStack(spacing: 12) {
				Button("Apply Stash") { viewModel.didRequestApplyStash() }
					.disabled(viewModel.selectedStash == nil || viewModel.isLoading)
				Menu("Stash Options", systemImage: "ellipsis.circle") {
					Button("Apply and Remove") { viewModel.didRequestPopStash() }
					Button("Delete Stash…", role: .destructive, action: onDelete)
				}
				.labelStyle(.iconOnly)
				.menuStyle(.borderlessButton)
				.menuIndicator(.hidden)
				.fixedSize()
				.disabled(viewModel.selectedStash == nil || viewModel.isLoading)
				Spacer()
				Toggle("Include Untracked", isOn: $viewModel.includeUntrackedInStash)
					.toggleStyle(.checkbox)
				Button("Save Stash") { viewModel.didRequestCreateStash() }
					.buttonStyle(.borderedProminent)
					.disabled(!viewModel.hasChanges || viewModel.isLoading)
			}
			if let message = viewModel.mutationMessage {
				Text(message).font(.caption).foregroundStyle(.secondary)
			}
		}
		.padding(12)
		.background(.bar)
	}
}
