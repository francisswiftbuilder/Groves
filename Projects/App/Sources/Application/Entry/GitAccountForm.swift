import CoreGitCredential
import SwiftUI

struct GitAccountForm: View {
	@Bindable var viewModel: GitAccountViewModel

	var body: some View {
		Form {
			if !viewModel.accounts.isEmpty {
				Section("GitHub Accounts") {
					Picker("Active account", selection: accountSelection) {
						if viewModel.account == nil {
							Text("Choose an account").tag(nil as GitCredentialDescriptor?)
						}
						ForEach(viewModel.accounts) { account in
							Text(account.account).tag(Optional(account))
						}
					}
					.disabled(viewModel.isConnecting)
					HStack {
						Button("Add Account…") { viewModel.beginAddingAccount() }
						Button("Replace Token…") { viewModel.beginReplacingToken() }
							.disabled(viewModel.account == nil)
						Button("Sign Out…", role: .destructive) { viewModel.beginSignOut() }
							.disabled(viewModel.account == nil)
					}
					.disabled(viewModel.isConnecting)
					Text(
						"Used by Groves to authenticate with GitHub. Changing accounts does not change commit identity."
					)
					.font(.caption)
					.foregroundStyle(.secondary)
				}
			}
			if viewModel.accounts.isEmpty || viewModel.tokenEntry != nil {
				GitAccountTokenSection(viewModel: viewModel)
			}
			Section("Commit Identity") {
				TextField(
					"Name", text: $viewModel.identity.name, prompt: Text("Commit author name")
				)
				.multilineTextAlignment(.leading)
				TextField(
					"Email", text: $viewModel.identity.email, prompt: Text("name@example.com")
				)
				.textContentType(.emailAddress)
				.autocorrectionDisabled()
				.multilineTextAlignment(.leading)
				Text(
					"This identity is written into commits. You can use your GitHub noreply email. A repository’s own identity takes precedence."
				)
				.font(.caption)
				.foregroundStyle(.secondary)
			}
			if let message = viewModel.errorMessage {
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
			if let message = viewModel.statusMessage {
				Section {
					Label(message, systemImage: "info.circle")
						.foregroundStyle(.secondary)
				}
			}
		}
		.formStyle(.grouped)
		.textFieldStyle(.roundedBorder)
		.confirmationDialog(
			"Sign out of \(viewModel.pendingSignOut?.account ?? "this account")?",
			isPresented: signOutPresentation
		) {
			Button("Sign Out", role: .destructive) { viewModel.confirmSignOut() }
			Button("Cancel", role: .cancel) { viewModel.cancelSignOut() }
		} message: {
			Text(
				"This account’s token will be removed from Groves. If other accounts are saved, another account becomes active. Your repositories and commit identity remain available."
			)
		}
	}

	private var signOutPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingSignOut != nil },
			set: { isPresented in
				if !isPresented { viewModel.cancelSignOut() }
			}
		)
	}

	private var accountSelection: Binding<GitCredentialDescriptor?> {
		Binding(
			get: { viewModel.account },
			set: { account in
				if let account { viewModel.switchAccount(to: account) }
			}
		)
	}
}
