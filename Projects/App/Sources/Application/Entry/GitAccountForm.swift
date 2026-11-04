import CoreGitCredential
import SwiftUI

struct GitAccountForm: View {
	@Bindable var viewModel: GitAccountViewModel
	let showsIdentity: Bool

	init(viewModel: GitAccountViewModel, showsIdentity: Bool = false) {
		self.viewModel = viewModel
		self.showsIdentity = showsIdentity
	}

	var body: some View {
		Form {
			Section("GitHub") {
				if viewModel.accounts.isEmpty {
					Text("No Accounts").foregroundStyle(.secondary)
				} else {
					Picker("Account", selection: accountSelection) {
						if viewModel.account == nil {
							Text("Choose an account").tag(nil as GitCredentialDescriptor?)
						}
						ForEach(viewModel.accounts) { account in
							Text(account.account).tag(Optional(account))
						}
					}
					.disabled(viewModel.isConnecting)
				}
				HStack {
					Button("Add Account…", action: viewModel.beginAddingAccount)
					Spacer()
					if !viewModel.accounts.isEmpty {
						Menu("Account Actions", systemImage: "ellipsis.circle") {
							Button("Replace Token…", action: viewModel.beginReplacingToken)
							Divider()
							Button("Sign Out…", role: .destructive, action: viewModel.beginSignOut)
						}
						.labelStyle(.iconOnly)
						.menuStyle(.borderlessButton)
						.menuIndicator(.hidden)
						.fixedSize()
						.disabled(viewModel.account == nil)
						.help("Account Actions")
					}
				}
				.disabled(viewModel.isConnecting)
			}
			if showsIdentity {
				GitIdentitySection(viewModel: viewModel, showsSaveActions: false)
			}
			if viewModel.tokenEntry == nil, let message = viewModel.errorMessage {
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
		}
		.formStyle(.grouped)
		.sheet(isPresented: tokenEntryPresentation) {
			GitAccountTokenSheet(viewModel: viewModel)
		}
		.confirmationDialog(
			"Sign out of \(viewModel.pendingSignOut?.account ?? "this account")?",
			isPresented: signOutPresentation
		) {
			Button("Sign Out", role: .destructive, action: viewModel.confirmSignOut)
			Button("Cancel", role: .cancel, action: viewModel.cancelSignOut)
		} message: {
			Text("Removes the saved token. Repositories and commit identity are kept.")
		}
	}

	private var tokenEntryPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.tokenEntry != nil },
			set: { if !$0 { viewModel.cancelTokenEntry() } })
	}

	private var signOutPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingSignOut != nil },
			set: { if !$0 { viewModel.cancelSignOut() } })
	}

	private var accountSelection: Binding<GitCredentialDescriptor?> {
		Binding(
			get: { viewModel.account },
			set: { if let account = $0 { viewModel.switchAccount(to: account) } })
	}
}
