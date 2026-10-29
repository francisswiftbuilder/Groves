import SwiftUI

struct GitAccountSetupView: View {
	let viewModel: GitAccountViewModel
	let isOnboarding: Bool

	var body: some View {
		GitAccountForm(viewModel: viewModel)
			.safeAreaInset(edge: .top) {
				VStack(alignment: .leading, spacing: 6) {
					Label(
						isOnboarding ? "Set Up Git in Groves" : "Accounts & Git",
						systemImage: "person.crop.circle.badge.checkmark"
					)
					.font(.title2.bold())
					Text("Connect your account once, then work with your repositories.")
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(20)
			}
			.safeAreaInset(edge: .bottom) {
				HStack {
					if isOnboarding {
						Button("Continue Without an Account") { viewModel.continueLocally() }
							.disabled(viewModel.isConnecting)
					}
					Spacer()
					Button(isOnboarding ? "Save and Continue" : "Save Git Identity") {
						viewModel.saveIdentity()
					}
					.buttonStyle(.borderedProminent)
					.disabled(!viewModel.identity.isValid || viewModel.isConnecting)
				}
				.padding(20)
			}
			.frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 580)
			.task { viewModel.load() }
	}
}
