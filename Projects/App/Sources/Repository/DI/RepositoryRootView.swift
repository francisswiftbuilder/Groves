import Foundation
import SwiftUI

struct RepositoryRootView: View {
	let viewModel: RepositoryTabsViewModel
	@ObservedObject var noticeCenter: RepositoryNoticeCenter
	@Binding var repositoryID: UUID?
	@State private var windowViewModel = RepositoryWindowViewModel()
	private let accountViewModel = AppDIContainer.shared.accountViewModel

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
		.safeAreaInset(edge: .top) {
			if let notice = noticeCenter.notice {
				RepositoryNoticeBanner(message: notice.message) {
					noticeCenter.dismiss()
				}
			}
		}
	}
}
