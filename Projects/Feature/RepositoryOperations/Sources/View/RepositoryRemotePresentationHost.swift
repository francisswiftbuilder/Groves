import SwiftUI

public struct RepositoryRemotePresentationHost<Content: View>: View {
	@Bindable private var viewModel: RemotesViewModel
	private let content: Content

	public init(
		viewModel: RemotesViewModel,
		@ViewBuilder content: () -> Content
	) {
		self.viewModel = viewModel
		self.content = content()
	}

	public var body: some View {
		content
			.sheet(item: $viewModel.editorPresentation) { presentation in
				RemoteEditorSheet(
					presentation: presentation, isLoading: viewModel.isLoading,
					errorMessage: viewModel.mutationErrorMessage
				) { name, fetchURL, pushURL in
					submitEditor(
						presentation,
						name: name,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				}
			}
			.sheet(item: $viewModel.pendingRename) { remote in
				RemoteRenameSheet(
					remote: remote, isLoading: viewModel.isLoading,
					errorMessage: viewModel.mutationErrorMessage
				) { newName in
					viewModel.didRequestRename(remote, to: newName)
				}
			}
			.sheet(isPresented: branchDeletionPresentation) {
				if case .deleteRemoteBranch(let branch) = viewModel.pendingConfirmation {
					BranchDeletionSheet(
						title: "Delete “\(branch.fullName)”?",
						message:
							"This branch will be deleted from “\(branch.remoteName)” for all collaborators.",
						optionTitle: localDeletionOptionTitle,
						unavailableReason: localDeletionUnavailableReason,
						onCancel: viewModel.didDismissConfirmation
					) { deleteLinkedBranch in
						viewModel.didConfirmPendingConfirmation(deleteLinkedBranch: deleteLinkedBranch)
					}
				}
			}
			.confirmationDialog(
				viewModel.pendingConfirmation?.title ?? "Confirm Remote Operation",
				isPresented: confirmationPresentation
			) {
				if let confirmation = viewModel.pendingConfirmation {
					Button(confirmation.actionTitle, role: .destructive) {
						viewModel.didConfirmPendingConfirmation()
					}
				}
				Button("Cancel", role: .cancel) {
					viewModel.didDismissConfirmation()
				}
			} message: {
				Text(viewModel.pendingConfirmation?.message ?? "")
			}
	}

	private var localDeletionOptionTitle: String {
		let names = viewModel.deletionLocalBranches.map { "“\($0.name)”" }.joined(separator: ", ")
		guard !names.isEmpty else { return "Also delete local branch" }
		let label =
			viewModel.deletionLocalBranches.count == 1
			? "Also delete local branch" : "Also delete local branches"
		return "\(label) \(names)"
	}

	private var localDeletionUnavailableReason: String? {
		if viewModel.deletionLocalBranches.isEmpty {
			return "No local branch tracks this remote branch."
		}
		if viewModel.deletionLocalBranches.contains(where: \.isCurrent) {
			return "Switch to another branch before deleting the checked-out local branch."
		}
		return nil
	}

	private var branchDeletionPresentation: Binding<Bool> {
		Binding(
			get: {
				if case .deleteRemoteBranch = viewModel.pendingConfirmation { return true }
				return false
			},
			set: { isPresented in
				if !isPresented { viewModel.didDismissConfirmation() }
			})
	}

	private var confirmationPresentation: Binding<Bool> {
		Binding(
			get: {
				guard let confirmation = viewModel.pendingConfirmation else { return false }
				if case .deleteRemoteBranch = confirmation { return false }
				return true
			},
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissConfirmation()
				}
			}
		)
	}

	private func submitEditor(
		_ presentation: RemoteEditorPresentation,
		name: String,
		fetchURL: String,
		pushURL: String?
	) {
		switch presentation {
		case .add:
			viewModel.didRequestAddRemote(
				name: name,
				fetchURL: fetchURL,
				pushURL: pushURL
			)
		case .edit(let remote):
			viewModel.didRequestUpdate(
				remote,
				fetchURL: fetchURL,
				pushURL: pushURL
			)
		}
	}
}
