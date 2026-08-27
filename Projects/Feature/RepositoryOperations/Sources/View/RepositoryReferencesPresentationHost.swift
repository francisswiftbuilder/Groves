import DomainGitInterface
import SwiftUI

public struct RepositoryReferencesPresentationHost<Content: View>: View {
	@ObservedObject private var viewModel: RepositoryReferencesViewModel
	private let onConfirmDeleteTag: (GitTag) -> Void
	private let content: Content

	public init(
		viewModel: RepositoryReferencesViewModel,
		onConfirmDeleteTag: @escaping (GitTag) -> Void,
		@ViewBuilder content: () -> Content
	) {
		self.viewModel = viewModel
		self.onConfirmDeleteTag = onConfirmDeleteTag
		self.content = content()
	}

	public var body: some View {
		content
			.sheet(isPresented: newBranchPresentation) {
				NewBranchSheet(
					name: $viewModel.newBranchName,
					onCancel: viewModel.didDismissNewBranch,
					onCreate: viewModel.didRequestCreateBranch
				)
			}
			.sheet(isPresented: newTagPresentation) {
				if let commit = viewModel.pendingTagCommit {
					NewTagSheet(
						commit: commit,
						name: $viewModel.newTagName,
						message: $viewModel.newTagMessage,
						onCancel: viewModel.didDismissNewTag,
						onCreate: viewModel.didRequestCreateTag
					)
				}
			}
			.sheet(item: $viewModel.pendingBranchRename) { _ in
				BranchRenameSheet(name: $viewModel.branchRenameName) {
					viewModel.didConfirmBranchRename()
				}
			}
			.confirmationDialog(
				viewModel.pendingConfirmation?.title ?? "Confirm Reference Operation",
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

	private var newBranchPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.isPresentingNewBranch },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewBranch()
				}
			}
		)
	}

	private var newTagPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingTagCommit != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewTag()
				}
			}
		)
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

	private func confirm(_ confirmation: RepositoryReferenceConfirmation) {
		if case .deleteTag(let tag) = confirmation {
			onConfirmDeleteTag(tag)
		}
		viewModel.didConfirmPendingConfirmation()
	}
}
