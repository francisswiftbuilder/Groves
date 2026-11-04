import SwiftUI

struct GitAccountSetupView: View {
	let viewModel: GitAccountViewModel
	let isOnboarding: Bool

	var body: some View {
		GitAccountForm(viewModel: viewModel, showsIdentity: isOnboarding)
			.safeAreaInset(edge: .top, spacing: 0) {
				if isOnboarding {
					Text("Set Up Git")
						.font(.headline)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 20)
						.padding(.top, 20)
				}
			}
			.safeAreaInset(edge: .bottom, spacing: 0) {
				if isOnboarding {
					HStack {
						Button("Not Now", action: viewModel.continueLocally)
							.disabled(viewModel.isConnecting)
						Spacer()
						Button("Continue", action: viewModel.saveIdentity)
							.buttonStyle(.borderedProminent)
							.keyboardShortcut(.defaultAction)
							.disabled(!viewModel.identity.isValid || viewModel.isConnecting)
					}
					.padding(20)
				}
			}
			.frame(minWidth: 480, idealWidth: 540, maxWidth: 680, minHeight: isOnboarding ? 440 : nil)
			.task { viewModel.load() }
	}
}
