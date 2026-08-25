import DomainGitInterface
import SwiftUI

struct RepositoryOperationBanner: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				Image(systemName: symbolName)
					.font(.title3)
					.foregroundStyle(viewModel.operationState.hasConflicts ? .orange : .secondary)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(title).font(.headline)
						if let progress = viewModel.operationState.operation?.progress {
							Text("\(progress.current) of \(progress.total)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					Text(statusMessage)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 12)
				if viewModel.operationState.hasConflicts {
					Button("View Conflicts") { viewModel.didViewConflicts() }
				}
				if viewModel.operationState.operation != nil {
					ViewThatFits(in: .horizontal) {
						HStack(spacing: 8) {
							secondaryActions
							continueButton
						}
						HStack(spacing: 8) {
							Menu("Actions") { secondaryActions }
							continueButton
						}
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			Divider()
		}
		.background(.bar)
		.accessibilityElement(children: .contain)
	}

	@ViewBuilder
	private var secondaryActions: some View {
		Button("Abort", role: .destructive) { viewModel.didPresentOperationAction(.abort) }
		if viewModel.operationState.operation?.kind != .merge {
			Button("Skip") { viewModel.didPresentOperationAction(.skip) }
		}
	}

	private var continueButton: some View {
		Button("Continue") { viewModel.didPerformOperationAction(.continue) }
			.buttonStyle(.borderedProminent)
			.disabled(viewModel.operationState.hasConflicts || viewModel.isLoading)
	}

	private var title: String {
		switch viewModel.operationState.operation?.kind {
		case .merge: return "Merge in Progress"
		case .rebase: return "Rebase in Progress"
		case .cherryPick: return "Cherry-pick in Progress"
		case .revert: return "Revert in Progress"
		case .none: return "Conflicts"
		}
	}

	private var symbolName: String {
		viewModel.operationState.hasConflicts
			? "exclamationmark.triangle.fill"
			: "arrow.triangle.2.circlepath"
	}

	private var statusMessage: String {
		let count = viewModel.operationState.conflicts.count
		guard count > 0 else { return "The repository is ready to continue." }
		return "Resolve \(count) conflict\(count == 1 ? "" : "s") before continuing."
	}

}
