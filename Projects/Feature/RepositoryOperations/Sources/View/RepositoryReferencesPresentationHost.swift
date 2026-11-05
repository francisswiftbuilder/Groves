import DomainGitInterface
import SwiftUI

public struct RepositoryReferencesPresentationHost<Content: View>: View {
	@Bindable private var viewModel: RepositoryReferencesViewModel
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
					startCommit: viewModel.pendingBranchStartCommit,
					isLoading: viewModel.isLoading,
					errorMessage: viewModel.mutationErrorMessage,
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
						isLoading: viewModel.isLoading,
						errorMessage: viewModel.mutationErrorMessage,
						onCancel: viewModel.didDismissNewTag,
						onCreate: viewModel.didRequestCreateTag
					)
				}
			}
			.sheet(item: $viewModel.pendingBranchRename) { _ in
				BranchRenameSheet(
					name: $viewModel.branchRenameName, isLoading: viewModel.isLoading,
					errorMessage: viewModel.mutationErrorMessage
				) {
					viewModel.didConfirmBranchRename()
				}
			}
			.sheet(isPresented: branchDeletionPresentation) {
				if case .deleteBranch(let branch) = viewModel.pendingConfirmation {
					BranchDeletionSheet(
						title: "Delete “\(branch.name)”?",
						message:
							"The local branch will be deleted. Remote deletion affects all collaborators.",
						optionTitle: viewModel.deletionRemoteBranch.map {
							"Also delete remote branch “\($0.fullName)”"
						}
							?? "Also delete remote branch",
						unavailableReason: viewModel.deletionRemoteBranch == nil
							? "This branch has no available upstream branch." : nil,
						onCancel: viewModel.didDismissPendingConfirmation
					) { deleteLinkedBranch in
						viewModel.didConfirmPendingConfirmation(deleteLinkedBranch: deleteLinkedBranch)
					}
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

	private var branchDeletionPresentation: Binding<Bool> {
		Binding(
			get: {
				if case .deleteBranch = viewModel.pendingConfirmation { return true }
				return false
			},
			set: { isPresented in
				if !isPresented { viewModel.didDismissPendingConfirmation() }
			})
	}

	private var confirmationPresentation: Binding<Bool> {
		Binding(
			get: {
				guard let confirmation = viewModel.pendingConfirmation else { return false }
				if case .deleteBranch = confirmation { return false }
				return true
			},
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
