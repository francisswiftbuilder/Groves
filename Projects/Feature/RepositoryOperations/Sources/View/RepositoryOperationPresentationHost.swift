import SwiftUI

public struct RepositoryOperationPresentationHost<Content: View>: View {
	@ObservedObject private var viewModel: RepositoryOperationViewModel
	private let content: Content

	public init(
		viewModel: RepositoryOperationViewModel,
		@ViewBuilder content: () -> Content
	) {
		self.viewModel = viewModel
		self.content = content()
	}

	public var body: some View {
		content
			.sheet(item: $viewModel.pendingMainlineAction) { action in
				MainlineSelectionSheet(action: action) { parent in
					viewModel.didPerformPendingMainlineAction(parent: parent)
				}
			}
			.sheet(item: $viewModel.pendingResetCommit) { commit in
				ResetCommitSheet(commit: commit, mode: $viewModel.resetMode) {
					viewModel.didConfirmReset()
				}
			}
			.confirmationDialog(
				viewModel.pendingConfirmation?.title ?? "Confirm Repository Operation",
				isPresented: confirmationPresentation
			) {
				if let confirmation = viewModel.pendingConfirmation {
					Button(confirmation.actionTitle, role: .destructive) {
						confirm(confirmation)
					}
				}
				Button("Cancel", role: .cancel) {
					viewModel.didDismissPendingConfirmation()
				}
			} message: {
				Text(viewModel.pendingConfirmation?.message ?? "")
			}
	}

	private var confirmationPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingConfirmation != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissPendingConfirmation()
				}
			}
		)
	}

	private func confirm(_ confirmation: RepositoryOperationConfirmation) {
		viewModel.didConfirmPendingConfirmation()
	}
}
