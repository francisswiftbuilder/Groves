import SwiftUI

struct ConflictPresentationHost<Content: View>: View {
	@ObservedObject private var viewModel: ConflictViewModel
	private let content: Content

	init(
		viewModel: ConflictViewModel,
		@ViewBuilder content: () -> Content
	) {
		self.viewModel = viewModel
		self.content = content()
	}

	var body: some View {
		content
			.confirmationDialog(
				viewModel.pendingConfirmation?.title ?? "Confirm Conflict Resolution",
				isPresented: confirmationPresentation
			) {
				if let confirmation = viewModel.pendingConfirmation {
					Button(confirmation.actionTitle, role: .destructive) {
						viewModel.didConfirmPendingConfirmation()
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
}
