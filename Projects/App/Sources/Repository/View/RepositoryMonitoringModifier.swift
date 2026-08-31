import Combine
import SwiftUI

struct RepositoryMonitoringModifier: ViewModifier {
	@Environment(\.scenePhase) private var scenePhase
	let viewModel: WorkspaceViewModel

	func body(content: Content) -> some View {
		content
			.onAppear {
				updateRepositoryMonitoring()
			}
			.onChange(of: scenePhase) { _, _ in
				updateRepositoryMonitoring()
			}
			.onReceive(viewModel.$repositoryURL.removeDuplicates()) { _ in
				updateRepositoryMonitoring()
			}
			.onDisappear {
				viewModel.setRepositoryMonitoringActive(false)
			}
	}

	private func updateRepositoryMonitoring() {
		viewModel.setRepositoryMonitoringActive(scenePhase == .active)
	}
}
