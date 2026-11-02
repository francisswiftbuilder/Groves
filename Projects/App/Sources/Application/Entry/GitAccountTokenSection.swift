import SwiftUI

struct GitAccountTokenSection: View {
	@Bindable var viewModel: GitAccountViewModel
	@FocusState private var isTokenFocused: Bool

	var body: some View {
		Section(isReplacingToken ? "Replace GitHub Token" : "Connect a GitHub Account") {
			SecureField(
				"Personal access token", text: $viewModel.token,
				prompt: Text(isReplacingToken ? "Paste a replacement token" : "Paste your GitHub token")
			)
			.textContentType(.password)
			.autocorrectionDisabled()
			.multilineTextAlignment(.leading)
			.focused($isTokenFocused)
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
			if !isReplacingToken {
				Text("Adding an account makes it active for new GitHub operations.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			HStack {
				if viewModel.isConnecting {
					ProgressView("Verifying account…").controlSize(.small)
				} else {
					Button(isReplacingToken ? "Verify and Replace Token" : "Verify and Add Account") {
						viewModel.connect()
					}
					.buttonStyle(.borderedProminent)
					.disabled(viewModel.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
				if viewModel.isConnecting || !viewModel.accounts.isEmpty {
					Button("Cancel") { viewModel.cancelTokenEntry() }
						.keyboardShortcut(.cancelAction)
				}
			}
			Text("GitHub HTTPS and SSH remote URLs work with this account. Other hosts require HTTPS.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.defaultFocus($isTokenFocused, true)
	}

	private var isReplacingToken: Bool {
		if case .replaceToken = viewModel.tokenEntry { return true }
		return false
	}
}
