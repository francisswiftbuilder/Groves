import Foundation
import SwiftUI

struct RepositoryRootView: View {
	let viewModel: RepositoryTabsViewModel
	let noticeCenter: RepositoryNoticeCenter
	let accountViewModel: GitAccountViewModel
	@Binding var repositoryID: UUID?
	@State private var windowViewModel = RepositoryWindowViewModel()

	var body: some View {
		Group {
			if !accountViewModel.hasCompletedSetup {
				GitAccountSetupView(viewModel: accountViewModel, isOnboarding: true)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				repositoryContent
			}
		}
		.background {
			NativeWindowTabConfigurator(repositoryID: repositoryID)
		}
	}

	private var repositoryContent: some View {
		RepositoryTabsView(
			viewModel: viewModel,
			windowViewModel: windowViewModel,
			repositoryID: $repositoryID
		)
		.modifier(
			RepositoryErrorAlertModifier(
				message: Binding(
					get: { noticeCenter.notice?.message },
					set: { message in
						if message == nil { noticeCenter.dismiss() }
					}
				),
				title: "Couldn’t Save Credentials"
			)
		)
	}
}
