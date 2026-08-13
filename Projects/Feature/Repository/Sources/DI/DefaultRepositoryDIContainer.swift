import FeatureRepositoryInterface
import SwiftUI

@MainActor
public final class DefaultRepositoryDIContainer: RepositoryDIContainer {
	private let dependencies: any RepositoryDIDependencies

	public init(dependencies: some RepositoryDIDependencies) {
		self.dependencies = dependencies
	}

	public func makeRootView() -> AnyView {
		do {
			return AnyView(
				RepositoryRootView(
					viewModel: RepositoryTabsViewModel(
						gitRepository: dependencies.makeGitRepository(),
						savedRepositoryStore: try dependencies.makeSavedRepositoryStore()
					)
				)
			)
		} catch {
			return AnyView(
				ContentUnavailableView(
					"Unable to Open Trees",
					systemImage: "externaldrive.badge.exclamationmark",
					description: Text(error.localizedDescription)
				)
			)
		}
	}
}

private struct RepositoryRootView: View {
	@StateObject private var viewModel: RepositoryTabsViewModel

	init(viewModel: RepositoryTabsViewModel) {
		_viewModel = StateObject(wrappedValue: viewModel)
	}

	var body: some View {
		RepositoryTabsView(viewModel: viewModel)
	}
}
