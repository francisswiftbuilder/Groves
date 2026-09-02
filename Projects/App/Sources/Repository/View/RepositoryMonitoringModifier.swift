import Combine
import SwiftUI

struct RepositoryMonitoringModifier: ViewModifier {
	@Environment(\.scenePhase) private var scenePhase
	let viewModel: WorkspaceViewModel

	func body(content: Content) -> some View {
		content
			.onAppear {
				viewModel.onAppear(isSceneActive: scenePhase == .active)
			}
			.onChange(of: scenePhase) { _, _ in
				viewModel.didChangeSceneActivation(scenePhase == .active)
			}
			.onReceive(viewModel.$repositoryURL.removeDuplicates()) { _ in
				viewModel.didChangeMonitoredRepository()
			}
			.onDisappear {
				viewModel.onDisappear()
			}
	}
}
