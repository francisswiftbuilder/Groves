import Foundation
import SwiftUI

struct RepositoryRootView: View {
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@ObservedObject var noticeCenter: RepositoryNoticeCenter
	@Binding var repositoryID: UUID?
	@StateObject private var windowViewModel = RepositoryWindowViewModel()
	@ObservedObject private var accountViewModel = AppDIContainer.shared.accountViewModel

	var body: some View {
		if !accountViewModel.hasCompletedSetup {
			GitAccountSetupView(viewModel: accountViewModel, isOnboarding: true)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			repositoryContent
		}
	}

	private var repositoryContent: some View {
		RepositoryTabsView(
			viewModel: viewModel,
			windowViewModel: windowViewModel,
			repositoryID: $repositoryID
		)
		.safeAreaInset(edge: .top) {
			if let notice = noticeCenter.notice {
				RepositoryNoticeBanner(message: notice.message) {
					noticeCenter.dismiss()
				}
			}
		}
	}
}
