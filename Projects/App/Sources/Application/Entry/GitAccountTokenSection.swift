import SwiftUI

struct GitAccountTokenSection: View {
	@Bindable var viewModel: GitAccountViewModel
	@FocusState private var isTokenFocused: Bool

	var body: some View {
		Section {
			SecureField("Token", text: $viewModel.token, prompt: Text("Personal access token"))
				.textContentType(.password)
				.autocorrectionDisabled()
				.multilineTextAlignment(.leading)
				.focused($isTokenFocused)
				.disabled(viewModel.isConnecting)
			Link(
				"Create a token on GitHub",
				destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
		} footer: {
			Text("Requires read and write access to repository contents.")
		}
		.defaultFocus($isTokenFocused, true)
	}
}
