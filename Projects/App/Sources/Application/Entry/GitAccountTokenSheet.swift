import SwiftUI

struct GitAccountTokenSheet: View {
	let viewModel: GitAccountViewModel

	var body: some View {
		Form {
			GitAccountTokenSection(viewModel: viewModel)
			if let message = viewModel.errorMessage {
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.font(.callout)
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			VStack(alignment: .leading, spacing: 4) {
				Text(isReplacingToken ? "Replace Token" : "Add GitHub Account").font(.headline)
				if case .replaceToken(let account) = viewModel.tokenEntry {
					Text(account.account).font(.callout).foregroundStyle(.secondary)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 20)
			.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack(spacing: 12) {
				if viewModel.isConnecting {
					ProgressView().controlSize(.small).accessibilityLabel("Connecting")
				}
				Spacer()
				Button("Cancel", role: .cancel, action: viewModel.cancelTokenEntry)
					.keyboardShortcut(.cancelAction)
				Button(isReplacingToken ? "Replace Token" : "Add Account", action: viewModel.connect)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(
						viewModel.isConnecting
							|| viewModel.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(20)
		}
		.frame(width: 480, height: 280)
		.interactiveDismissDisabled(viewModel.isConnecting)
		.onDisappear(perform: viewModel.cancelTokenEntry)
	}

	private var isReplacingToken: Bool {
		if case .replaceToken = viewModel.tokenEntry { return true }
		return false
	}
}
