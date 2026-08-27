import DomainGitInterface
import FeatureRepositoryChanges
import SwiftUI

struct StashActionBar: View {
	@ObservedObject var viewModel: StashesViewModel
	@ObservedObject private var changesViewModel: ChangesViewModel
	let onDelete: () -> Void

	init(
		viewModel: StashesViewModel,
		changesViewModel: ChangesViewModel,
		onDelete: @escaping () -> Void
	) {
		self.viewModel = viewModel
		_changesViewModel = ObservedObject(wrappedValue: changesViewModel)
		self.onDelete = onDelete
	}

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

			Toggle("Include Untracked Files", isOn: $viewModel.includeUntrackedInStash)
				.toggleStyle(.checkbox)

			Button("Stash") {
				viewModel.didRequestCreateStash()
			}
			.buttonStyle(.borderedProminent)
			.disabled(changesViewModel.changes.isEmpty || viewModel.isLoading)

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
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
