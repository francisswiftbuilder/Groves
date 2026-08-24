import FeatureRepositoryInterface
import Foundation
import SwiftUI

@MainActor
public final class DefaultRepositoryDIContainer: RepositoryDIContainer {
	private let viewModelResult: Result<RepositoryTabsViewModel, Error>

	public init(dependencies: some RepositoryDIDependencies) {
		viewModelResult = Result {
			let contentUseCase = dependencies.makeRepositoryContentUseCase()
			let changesUseCase = dependencies.makeRepositoryChangesUseCase()
			let referencesUseCase = dependencies.makeRepositoryReferencesUseCase()
			let stashesUseCase = dependencies.makeRepositoryStashesUseCase()
			return RepositoryTabsViewModel(
				useCase: try dependencies.makeRepositoryTabsUseCase(),
				makeWorkspaceViewModel: { repositoryURL in
					WorkspaceViewModel(
						contentUseCase: contentUseCase,
						changesUseCase: changesUseCase,
						referencesUseCase: referencesUseCase,
						stashesUseCase: stashesUseCase,
						repositoryURL: repositoryURL
					)
				}
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
