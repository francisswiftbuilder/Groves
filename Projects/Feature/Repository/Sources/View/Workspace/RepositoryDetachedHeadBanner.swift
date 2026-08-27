import SwiftUI

struct RepositoryDetachedHeadBanner: View {
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel

	init(viewModel: RepositoryOperationViewModel) {
		_operationViewModel = ObservedObject(wrappedValue: viewModel)
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				Image(systemName: "scope")
					.font(.title3)
					.foregroundStyle(.orange)
					.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 2) {
					Text("Detached HEAD")
						.font(.headline)
					Text("Create a branch here or switch to an existing local branch before making changes.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Spacer(minLength: 12)

				Button("Create Branch…", systemImage: "arrow.triangle.branch") {
					operationViewModel.didPresentNewBranch()
				}

				Menu("Switch Branch", systemImage: "arrow.left.arrow.right") {
					ForEach(operationViewModel.branches) { branch in
						Button(branch.name) {
							operationViewModel.didRequestSwitchBranch(branch)
						}
					}
				}
				.disabled(operationViewModel.branches.isEmpty)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)

			Divider()
		}
		.background(.bar)
	}
}
