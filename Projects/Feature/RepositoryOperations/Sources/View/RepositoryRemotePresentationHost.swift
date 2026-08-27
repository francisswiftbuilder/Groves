import SwiftUI

public struct RepositoryRemotePresentationHost<Content: View>: View {
	@ObservedObject private var viewModel: RemotesViewModel
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
				RemoteEditorSheet(presentation: presentation) { name, fetchURL, pushURL in
					submitEditor(
						presentation,
						name: name,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				}
			}
			.sheet(item: $viewModel.pendingRename) { remote in
				RemoteRenameSheet(remote: remote) { newName in
					viewModel.didRequestRename(remote, to: newName)
					viewModel.didDismissRename()
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

	private var confirmationPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingConfirmation != nil },
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
		viewModel.didDismissEditor()
	}
}
