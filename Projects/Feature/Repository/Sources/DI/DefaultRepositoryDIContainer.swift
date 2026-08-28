import FeatureRepositoryInterface
import Foundation
import SwiftUI

@MainActor
public final class DefaultRepositoryDIContainer: RepositoryDIContainer {
	private let viewModelResult: Result<RepositoryTabsViewModel, Error>
	private let noticeCenter: RepositoryNoticeCenter

	public init(dependencies: some RepositoryDIDependencies) {
		noticeCenter = dependencies.makeRepositoryNoticeCenter()
		viewModelResult = Result {
			let workspaceAssembly = RepositoryWorkspaceAssembly(
				dependencies: .init(
					contentUseCase: dependencies.makeRepositoryContentUseCase(),
					changesUseCase: dependencies.makeRepositoryChangesUseCase(),
					referencesUseCase: dependencies.makeRepositoryReferencesUseCase(),
					stashesUseCase: dependencies.makeRepositoryStashesUseCase(),
					operationsUseCase: dependencies.makeRepositoryOperationsUseCase(),
					externalEditorOpener: dependencies.makeRepositoryExternalEditorOpener()
				)
			)
			return RepositoryTabsViewModel(
				useCase: try dependencies.makeRepositoryTabsUseCase(),
				makeWorkspace: { repositoryURL in
					workspaceAssembly.makeWorkspace(repositoryURL: repositoryURL)
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
					noticeCenter: noticeCenter,
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
