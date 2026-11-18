import FeatureRepositoryOperations
import SwiftUI

struct RepositoryMonitoringModifier: ViewModifier {
	@Environment(\.appearsActive) private var appearsActive
	@Environment(\.scenePhase) private var scenePhase
	let viewModel: WorkspaceViewModel
	let syncViewModel: RepositorySyncViewModel

	private var isWindowActive: Bool {
		scenePhase == .active || appearsActive
	}

	func body(content: Content) -> some View {
		content
			.onAppear {
				viewModel.onAppear(isSceneActive: isWindowActive)
				syncViewModel.updateAutomaticFetching(isActive: isWindowActive)
			}
			.onChange(of: isWindowActive) { _, isActive in
				viewModel.didChangeSceneActivation(isActive)
				syncViewModel.updateAutomaticFetching(isActive: isActive)
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
