import FeatureRepositoryOperations
import SwiftUI

struct RepositoryMonitoringModifier: ViewModifier {
	@Environment(\.scenePhase) private var scenePhase
	let viewModel: WorkspaceViewModel
	let syncViewModel: RepositorySyncViewModel

	func body(content: Content) -> some View {
		content
			.onAppear {
				viewModel.onAppear(isSceneActive: scenePhase == .active)
				syncViewModel.updateAutomaticFetching(isActive: scenePhase == .active)
			}
			.onChange(of: scenePhase) { _, _ in
				viewModel.didChangeSceneActivation(scenePhase == .active)
				syncViewModel.updateAutomaticFetching(isActive: scenePhase == .active)
			}
			.onChange(of: viewModel.repositoryURL) { _, _ in
				viewModel.didChangeMonitoredRepository()
			}
			.onDisappear {
				viewModel.onDisappear()
				syncViewModel.updateAutomaticFetching(isActive: false)
			}
	}
}
