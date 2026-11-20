import SwiftUI

struct PluminonSettingsView: View {
	@State private var selectedTab = PluminonSettingsTab.general
	private let accountViewModel: GitAccountViewModel

	init(accountViewModel: GitAccountViewModel) {
		self.accountViewModel = accountViewModel
	}

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab("General", systemImage: "gearshape", value: PluminonSettingsTab.general) {
				GeneralSettingsView(accountViewModel: accountViewModel)
			}
			Tab("Accounts", systemImage: "person.crop.circle", value: PluminonSettingsTab.accounts) {
				GitAccountSetupView(viewModel: accountViewModel, isOnboarding: false)
			}
		}
		.frame(width: 540, height: selectedTab == .general ? 420 : 280)
	}

}

#Preview {
	PluminonSettingsView(accountViewModel: GitAccountViewModel())
}
