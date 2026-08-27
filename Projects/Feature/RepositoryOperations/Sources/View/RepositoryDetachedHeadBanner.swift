import SwiftUI

public struct RepositoryDetachedHeadBanner: View {
	@ObservedObject private var viewModel: RepositoryReferencesViewModel

	public init(viewModel: RepositoryReferencesViewModel) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
	}

	public var body: some View {
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
					viewModel.didPresentNewBranch()
				}

				Menu("Switch Branch", systemImage: "arrow.left.arrow.right") {
					ForEach(viewModel.branches) { branch in
						Button(branch.name) {
							viewModel.didRequestSwitchBranch(branch)
						}
					}
				}
				.disabled(viewModel.branches.isEmpty)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)

			Divider()
		}
		.background(.bar)
	}
}
