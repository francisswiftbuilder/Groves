import FeatureRepositoryInterface
import Foundation
import SwiftUI

@MainActor
public final class DefaultRepositoryDIContainer: RepositoryDIContainer {
	private let viewModelResult: Result<RepositoryTabsViewModel, Error>

	public init(dependencies: some RepositoryDIDependencies) {
		viewModelResult = Result {
			RepositoryTabsViewModel(
				gitRepository: dependencies.makeGitRepository(),
				savedRepositoryStore: try dependencies.makeSavedRepositoryStore()
			)
		}
	}

	public func makeRootView(repositoryID: Binding<UUID?>) -> AnyView {
		switch viewModelResult {
		case .success(let viewModel):
			return AnyView(
				RepositoryRootView(
					viewModel: viewModel,
					repositoryID: repositoryID
				)
			)
		case .failure(let error):
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
