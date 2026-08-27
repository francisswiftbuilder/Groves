import DomainGitInterface
import SwiftUI

struct RemoteActionBar: View {
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	let preferredRemoteName: String?
	let onAdd: () -> Void

	init(
		syncViewModel: RepositorySyncViewModel,
		preferredRemoteName: String?,
		onAdd: @escaping () -> Void
	) {
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		self.preferredRemoteName = preferredRemoteName
		self.onAdd = onAdd
	}

	var body: some View {
		HStack(spacing: 10) {
			Button("Add Remote…", systemImage: "plus") {
				onAdd()
			}

			Label(preferredRemoteName ?? "Remote", systemImage: "icloud")
				.font(.callout)
				.foregroundStyle(.secondary)

			Spacer()

			Button("Pull", systemImage: "arrow.down") {
				syncViewModel.didRequestPull()
			}
			.disabled(preferredRemoteName == nil || syncViewModel.isLoading)

			RepositoryPushMenu(
				viewModel: syncViewModel,
				preferredRemoteName: preferredRemoteName
			)
			.disabled(preferredRemoteName == nil || syncViewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
