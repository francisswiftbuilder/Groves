import SwiftUI

struct GitIdentitySection: View {
	@Bindable var viewModel: GitAccountViewModel
	let showsSaveActions: Bool

	var body: some View {
		Section {
			TextField("Name", text: $viewModel.identity.name, prompt: Text("Commit author name"))
				.multilineTextAlignment(.leading)
			TextField("Email", text: $viewModel.identity.email, prompt: Text("name@example.com"))
				.textContentType(.emailAddress)
				.autocorrectionDisabled()
				.multilineTextAlignment(.leading)
			if showsSaveActions {
				HStack {
					Spacer()
					Button("Revert", action: viewModel.restoreIdentity)
						.disabled(!viewModel.hasIdentityChanges || viewModel.isConnecting)
					Button("Save", action: viewModel.saveIdentity)
						.keyboardShortcut("s", modifiers: .command)
						.disabled(!viewModel.canSaveIdentity)
				}
			}
		} header: {
			Text("Commit Identity")
		} footer: {
			Text(
				viewModel.hasIdentityChanges && !viewModel.identity.isValid
					? "Enter a name and valid email address."
					: "Repository settings override this identity.")
		}
		.onSubmit {
			if showsSaveActions, viewModel.canSaveIdentity { viewModel.saveIdentity() }
		}
	}
}
