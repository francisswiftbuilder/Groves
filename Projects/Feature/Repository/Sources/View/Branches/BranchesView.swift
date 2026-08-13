import DomainGitInterface
import SwiftUI

struct BranchesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.branches.isEmpty {
				EmptyStateView(
					title: "No Branches",
					message: "Local branches will appear here.",
					systemImage: "arrow.triangle.branch"
				)
			} else {
				List(selection: $viewModel.selectedBranchID) {
					ForEach(viewModel.branches) { branch in
						BranchRow(branch: branch)
							.tag(branch.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Branches")
		.navigationSubtitle("\(viewModel.branches.count) local branches")
		.safeAreaInset(edge: .bottom) {
			BranchActionBar(viewModel: viewModel)
		}
	}
}

private struct BranchRow: View {
	let branch: GitBranch

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(branch.isCurrent ? .green : .secondary)
				.frame(width: 20)
				.accessibilityLabel(branch.isCurrent ? "Current branch" : "Branch")
			VStack(alignment: .leading, spacing: 3) {
				Text(branch.name)
				HStack(spacing: 8) {
					Text(branch.shortHash)
						.font(.system(.caption, design: .monospaced))
					if let upstream = branch.upstream {
						Text(upstream)
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

private struct BranchActionBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		HStack(spacing: 10) {
			Label("New Branch", systemImage: "arrow.triangle.branch")
				.font(.callout)
				.foregroundStyle(.secondary)
			TextField("New branch name", text: $viewModel.newBranchName)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: 280)
				.onSubmit {
					viewModel.didRequestCreateBranch()
				}
			Button("Create") {
				viewModel.didRequestCreateBranch()
			}
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			Spacer()
			Button("Switch") {
				viewModel.didRequestSwitchBranch()
			}
			.disabled(viewModel.selectedBranch?.isCurrent != false)
			Button("Delete", role: .destructive) {
				viewModel.didRequestDeleteBranch()
			}
			.disabled(viewModel.selectedBranch?.isCurrent != false)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
