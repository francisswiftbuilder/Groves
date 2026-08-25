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
			let operationsUseCase = dependencies.makeRepositoryOperationsUseCase()
			let externalEditorOpener = dependencies.makeRepositoryExternalEditorOpener()
			return RepositoryTabsViewModel(
				useCase: try dependencies.makeRepositoryTabsUseCase(),
				makeWorkspaceViewModel: { repositoryURL in
					WorkspaceViewModel(
						contentUseCase: contentUseCase,
						changesUseCase: changesUseCase,
						referencesUseCase: referencesUseCase,
						stashesUseCase: stashesUseCase,
						operationsUseCase: operationsUseCase,
						externalEditorOpener: externalEditorOpener,
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
