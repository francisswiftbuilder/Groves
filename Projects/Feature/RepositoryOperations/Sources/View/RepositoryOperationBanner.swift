import DomainGitInterface
import SwiftUI

public struct RepositoryOperationBanner: View {
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel

	public init(viewModel: RepositoryOperationViewModel) {
		_operationViewModel = ObservedObject(wrappedValue: viewModel)
	}

	public var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				Image(systemName: symbolName)
					.font(.title3)
					.foregroundStyle(operationViewModel.operationState.hasConflicts ? .orange : .secondary)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(title).font(.headline)
						if let progress = operationViewModel.operationState.operation?.progress {
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
				if operationViewModel.operationState.hasConflicts {
					Button("View Conflicts") { operationViewModel.didViewConflicts() }
				}
				if operationViewModel.operationState.operation != nil {
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
		Button("Abort", role: .destructive) { operationViewModel.didPresentOperationAction(.abort) }
		if operationViewModel.operationState.operation?.kind != .merge {
			Button("Skip") { operationViewModel.didPresentOperationAction(.skip) }
		}
	}

	private var continueButton: some View {
		Button("Continue") { operationViewModel.didPerformOperationAction(.continue) }
			.buttonStyle(.borderedProminent)
			.disabled(operationViewModel.operationState.hasConflicts || operationViewModel.isLoading)
	}

	private var title: String {
		switch operationViewModel.operationState.operation?.kind {
		case .merge: return "Merge in Progress"
		case .rebase: return "Rebase in Progress"
		case .cherryPick: return "Cherry-pick in Progress"
		case .revert: return "Revert in Progress"
		case .none: return "Conflicts"
		}
	}

	private var symbolName: String {
		operationViewModel.operationState.hasConflicts
			? "exclamationmark.triangle.fill"
			: "arrow.triangle.2.circlepath"
	}

	private var statusMessage: String {
		let count = operationViewModel.operationState.conflicts.count
		guard count > 0 else { return "The repository is ready to continue." }
		return "Resolve \(count) conflict\(count == 1 ? "" : "s") before continuing."
	}

}
