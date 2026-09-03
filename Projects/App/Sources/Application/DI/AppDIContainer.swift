import DataGit
import DomainGit
import DomainGitInterface
import Foundation
import SwiftUI

@MainActor
final class AppDIContainer {
	static let shared = AppDIContainer()
	let windowTabCoordinator: any RepositoryWindowTabCoordinating
	private let noticeCenter: RepositoryNoticeCenter
	private let viewModelResult: Result<RepositoryTabsViewModel, Error>

	private init() {
		let noticeCenter = RepositoryNoticeCenter()
		self.noticeCenter = noticeCenter
		let repository = LocalGitRepository(
			configuration: GitProcessConfiguration(
				askPassHelperURL: GrovesAskPassLocator.bundledHelperURL,
				noticeHandler: { notice in noticeCenter.post(notice) }
			)
		)
		let result: Result<RepositoryTabsViewModel, Error> = Result {
			let contentUseCase = DefaultRepositoryContentUseCase(repository: repository)
			let workspaceAssembly = RepositoryWorkspaceAssembly(
				dependencies: .init(
					contentUseCase: contentUseCase,
					changesUseCase: DefaultRepositoryChangesUseCase(
						repository: repository,
						content: contentUseCase
					),
					referencesUseCase: DefaultRepositoryReferencesUseCase(
						repository: repository,
						content: contentUseCase
					),
					stashesUseCase: DefaultRepositoryStashesUseCase(
						repository: repository,
						content: contentUseCase
					),
					operationsUseCase: DefaultRepositoryOperationsUseCase(
						repository: repository,
						content: contentUseCase
					),
					externalEditorOpener: WorkspaceExternalEditorOpener()
				)
			)
			return RepositoryTabsViewModel(
				dependencies: .init(
					useCase: DefaultRepositoryTabsUseCase(
						repository: repository,
						store: try SwiftDataSavedRepositoryStore()
					),
					makeWorkspace: { repositoryURL in
						workspaceAssembly.makeWorkspace(repositoryURL: repositoryURL)
					}
				)
			)
		}
		viewModelResult = result
		var coordinator: NativeWindowTabCoordinator?
		coordinator = NativeWindowTabCoordinator { [weak coordinator] repositoryID in
			AppDIContainer.makeRepositoryRootView(
				viewModelResult: result,
				noticeCenter: noticeCenter,
				windowTabCoordinator: coordinator,
				repositoryID: repositoryID
			)
		}
		windowTabCoordinator = coordinator!
	}

	func makeRepositoryRootView(repositoryID: Binding<UUID?>) -> AnyView {
		Self.makeRepositoryRootView(
			viewModelResult: viewModelResult,
			noticeCenter: noticeCenter,
			windowTabCoordinator: windowTabCoordinator,
			repositoryID: repositoryID
		)
	}

	private static func makeRepositoryRootView(
		viewModelResult: Result<RepositoryTabsViewModel, Error>,
		noticeCenter: RepositoryNoticeCenter,
		windowTabCoordinator: (any RepositoryWindowTabCoordinating)?,
		repositoryID: Binding<UUID?>
	) -> AnyView {
		switch viewModelResult {
		case .success(let viewModel):
			return AnyView(
				RepositoryRootView(
					viewModel: viewModel,
					noticeCenter: noticeCenter,
					repositoryID: repositoryID
				)
				.environment(\.windowTabCoordinator, windowTabCoordinator)
			)
		case .failure(let error):
			return AnyView(
				ContentUnavailableView(
					"Unable to Open Groves",
					systemImage: "externaldrive.badge.exclamationmark",
					description: Text(error.localizedDescription)
				)
			)
		}
	}
}
