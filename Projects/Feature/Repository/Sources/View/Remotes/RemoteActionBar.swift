import DomainGitInterface
import SwiftUI

struct RemoteActionBar: View {
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	let onAdd: () -> Void

	init(
		operationViewModel: RepositoryOperationViewModel,
		onAdd: @escaping () -> Void
	) {
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		self.onAdd = onAdd
	}

	var body: some View {
		HStack(spacing: 10) {
			Button("Add Remote…", systemImage: "plus") {
				onAdd()
			}

			Label(operationViewModel.selectedRemote?.name ?? "Remote", systemImage: "icloud")
				.font(.callout)
				.foregroundStyle(.secondary)

			Spacer()

			Button("Pull", systemImage: "arrow.down") {
				operationViewModel.didRequestPull()
			}
			.disabled(operationViewModel.selectedRemote == nil || operationViewModel.isLoading)

			RepositoryPushMenu(
				viewModel: operationViewModel,
				preferredRemoteName: operationViewModel.selectedRemote?.name
			)
			.disabled(operationViewModel.selectedRemote == nil || operationViewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
