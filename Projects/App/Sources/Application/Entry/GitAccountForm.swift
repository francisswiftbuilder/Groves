import SwiftUI

struct GitAccountForm: View {
	@ObservedObject var viewModel: GitAccountViewModel
	@State private var isConfirmingSignOut = false

	var body: some View {
		Form {
			Section {
				Label("App-specific Git settings", systemImage: "checkmark.shield")
				Text(
					"Groves uses its own HTTPS credentials and commit identity. Your terminal’s global Git settings are not imported. Repository-level settings still apply."
				)
				.font(.callout)
				.foregroundStyle(.secondary)
			}
			Section("GitHub Account") {
				if let account = viewModel.account {
					LabeledContent("Saved account", value: account.account)
					Button("Sign Out…", role: .destructive) { isConfirmingSignOut = true }
						.disabled(viewModel.isConnecting)
				}
				SecureField("Personal access token", text: $viewModel.token)
					.textContentType(.password)
					.autocorrectionDisabled()
					.disabled(viewModel.isConnecting)
					.onSubmit { viewModel.connect() }
				Link(
					"Create a token on GitHub",
					destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
				Text(
					"Select the repositories you need. Contents: Read and write is needed to push. Organization approval or additional workflow permissions may also be required."
				)
				.font(.caption)
				.foregroundStyle(.secondary)
				if viewModel.isConnecting {
					HStack {
						ProgressView("Verifying account…").controlSize(.small)
						Button("Cancel") { viewModel.cancelConnection() }
					}
				} else {
					Button(viewModel.account == nil ? "Connect GitHub" : "Verify and Replace Token") {
						viewModel.connect()
					}
					.buttonStyle(.borderedProminent)
					.disabled(viewModel.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
				Text(
					"Use HTTPS remote URLs with this account. SSH remotes must be changed to HTTPS in repository Remotes."
				)
				.font(.caption)
				.foregroundStyle(.secondary)
			}
			Section("Commit Identity") {
				TextField("Name", text: $viewModel.identity.name)
				TextField("Email", text: $viewModel.identity.email)
					.autocorrectionDisabled()
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
		.confirmationDialog("Sign out of Groves?", isPresented: $isConfirmingSignOut) {
			Button("Sign Out", role: .destructive) { viewModel.signOut() }
		} message: {
			Text(
				"The saved GitHub token will be removed from Groves. Your repositories and commit identity remain available."
			)
		}
	}
}
