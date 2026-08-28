import DataGit
import DomainGit
import DomainGitInterface
import Foundation
import SwiftUI

@MainActor
final class AppDIContainer {
	static let shared = AppDIContainer()
	private let noticeCenter: RepositoryNoticeCenter
	private let viewModelResult: Result<RepositoryTabsViewModel, Error>

	private init() {
		let noticeCenter = RepositoryNoticeCenter()
		self.noticeCenter = noticeCenter
		let repository = LocalGitRepository(
			configuration: GitProcessConfiguration(
				askPassHelperURL: TreesAskPassLocator.bundledHelperURL,
				noticeHandler: { notice in noticeCenter.post(notice) }
			)
		)
		viewModelResult = Result {
			let workspaceAssembly = RepositoryWorkspaceAssembly(
				dependencies: .init(
					contentUseCase: RepositoryUseCaseFactory.makeContentUseCase(
						repository: repository
					),
					changesUseCase: RepositoryUseCaseFactory.makeChangesUseCase(
						repository: repository
					),
					referencesUseCase: RepositoryUseCaseFactory.makeReferencesUseCase(
						repository: repository
					),
					stashesUseCase: RepositoryUseCaseFactory.makeStashesUseCase(
						repository: repository
					),
					operationsUseCase: RepositoryUseCaseFactory.makeOperationsUseCase(
						repository: repository
					),
					externalEditorOpener: WorkspaceExternalEditorOpener()
				)
			)
			return RepositoryTabsViewModel(
				useCase: RepositoryUseCaseFactory.makeTabsUseCase(
					repository: repository,
					savedRepositoryStore: try SwiftDataSavedRepositoryStore()
				),
				makeWorkspace: { repositoryURL in
					workspaceAssembly.makeWorkspace(repositoryURL: repositoryURL)
				}
			)
		}
	}

	func makeRepositoryRootView(repositoryID: Binding<UUID?>) -> AnyView {
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
