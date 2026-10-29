import DomainGitInterface
import SwiftUI

struct StashActionBar: View {
	@Bindable var viewModel: StashesViewModel
	let onDelete: () -> Void

	init(
		viewModel: StashesViewModel,
		onDelete: @escaping () -> Void
	) {
		self.viewModel = viewModel
		self.onDelete = onDelete
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			controls
			if let message = viewModel.mutationMessage {
				Label(message, systemImage: "info.circle")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}

	private var controls: some View {
		HStack(spacing: 10) {
			Label("New Stash", systemImage: "archivebox")
				.font(.callout)
				.foregroundStyle(.secondary)

			TextField("Message (optional)", text: $viewModel.newStashMessage)
				.textFieldStyle(.roundedBorder)
				.onSubmit {
					viewModel.didRequestCreateStash()
				}

			Toggle("Include Untracked Files", isOn: $viewModel.includeUntrackedInStash)
				.toggleStyle(.checkbox)

			Button("Stash") {
				viewModel.didRequestCreateStash()
			}
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.hasChanges == false || viewModel.isLoading)

			Button("Apply") {
				viewModel.didRequestApplyStash()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)

			Button("Pop") {
				viewModel.didRequestPopStash()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)

			Button("Delete…", role: .destructive) {
				onDelete()
			}
			.disabled(viewModel.selectedStash == nil || viewModel.isLoading)
		}
	}
}
