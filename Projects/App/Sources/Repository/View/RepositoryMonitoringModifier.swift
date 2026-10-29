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
			.onChange(of: viewModel.repositoryURL) { _, _ in
				viewModel.didChangeMonitoredRepository()
			}
			.onDisappear {
				viewModel.onDisappear()
			}
	}
}
