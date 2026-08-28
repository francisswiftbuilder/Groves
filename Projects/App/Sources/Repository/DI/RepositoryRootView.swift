import Foundation
import SwiftUI

struct RepositoryRootView: View {
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@ObservedObject var noticeCenter: RepositoryNoticeCenter
	@Binding var repositoryID: UUID?
	@StateObject private var windowViewModel = RepositoryWindowViewModel()

	var body: some View {
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
