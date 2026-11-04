import SwiftUI

struct GrovesSettingsView: View {
	@State private var selectedTab = GrovesSettingsTab.general
	private let accountViewModel: GitAccountViewModel

	init(accountViewModel: GitAccountViewModel) {
		self.accountViewModel = accountViewModel
	}

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab("General", systemImage: "gearshape", value: GrovesSettingsTab.general) {
				GeneralSettingsView(accountViewModel: accountViewModel)
			}
			Tab("Accounts", systemImage: "person.crop.circle", value: GrovesSettingsTab.accounts) {
				GitAccountSetupView(viewModel: accountViewModel, isOnboarding: false)
			}
		}
		.frame(width: 540, height: selectedTab == .general ? 420 : 280)
	}

}

#Preview {
	GrovesSettingsView(accountViewModel: GitAccountViewModel())
}
