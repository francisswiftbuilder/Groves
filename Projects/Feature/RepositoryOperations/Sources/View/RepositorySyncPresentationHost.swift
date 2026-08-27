import SwiftUI

public struct RepositorySyncPresentationHost<Content: View>: View {
	@ObservedObject private var viewModel: RepositorySyncViewModel
	private let content: Content

	public init(
		viewModel: RepositorySyncViewModel,
		@ViewBuilder content: () -> Content
	) {
		self.viewModel = viewModel
		self.content = content()
	}

	public var body: some View {
		content
			.confirmationDialog(
				viewModel.pendingConfirmation?.title ?? "Confirm Sync Operation",
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
			.confirmationDialog(
				pullDivergenceTitle,
				isPresented: pullDivergencePresentation
			) {
				Button("Rebase onto Upstream") {
					viewModel.didResolvePull(using: .rebase)
				}
				Button("Merge Upstream") {
					viewModel.didResolvePull(using: .merge)
				}
				Button("Cancel", role: .cancel) {
					viewModel.didDismissPullDivergence()
				}
			} message: {
				if let divergence = viewModel.pendingPullDivergence {
					Text(
						"\(divergence.upstream) · ↑\(divergence.aheadCount) · ↓\(divergence.behindCount)"
					)
				}
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

	private var pullDivergencePresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingPullDivergence != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissPullDivergence()
				}
			}
		)
	}

	private var pullDivergenceTitle: String {
		guard let divergence = viewModel.pendingPullDivergence else {
			return "Branches Have Diverged"
		}
		return "Choose How to Integrate \(divergence.upstream)"
	}
}
