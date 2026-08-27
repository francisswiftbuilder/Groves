import DataGit
import DomainGit
import DomainGitInterface
import FeatureRepository
import FeatureRepositoryInterface
import Foundation
import SwiftUI

@MainActor
final class AppDIContainer: RepositoryDIDependencies {
	static let shared = AppDIContainer()
	private let repository: any GitRepository
	private let savedRepositoryStoreResult: Result<any SavedRepositoryStore, Error>
	private lazy var repositoryDIContainer = DefaultRepositoryDIContainer(dependencies: self)

	private init() {
		repository = LocalGitRepository(
			configuration: GitProcessConfiguration(
				askPassHelperURL: TreesAskPassLocator.bundledHelperURL
			)
		)
		savedRepositoryStoreResult = Result {
			try SwiftDataSavedRepositoryStore()
		}
	}

	func makeRepositoryTabsUseCase() throws -> any RepositoryTabsUseCase {
		RepositoryUseCaseFactory.makeTabsUseCase(
			repository: repository,
			savedRepositoryStore: try savedRepositoryStoreResult.get()
		)
	}

	func makeRepositoryContentUseCase() -> any RepositoryContentUseCase {
		RepositoryUseCaseFactory.makeContentUseCase(repository: repository)
	}

	func makeRepositoryChangesUseCase() -> any RepositoryChangesUseCase {
		RepositoryUseCaseFactory.makeChangesUseCase(repository: repository)
	}

	func makeRepositoryReferencesUseCase() -> any RepositoryReferencesUseCase {
		RepositoryUseCaseFactory.makeReferencesUseCase(repository: repository)
	}

	func makeRepositoryStashesUseCase() -> any RepositoryStashesUseCase {
		RepositoryUseCaseFactory.makeStashesUseCase(repository: repository)
	}

	func makeRepositoryOperationsUseCase() -> any RepositoryOperationsUseCase {
		RepositoryUseCaseFactory.makeOperationsUseCase(repository: repository)
	}

	func makeRepositoryExternalEditorOpener() -> any RepositoryExternalEditorOpening {
		WorkspaceExternalEditorOpener()
	}

	func makeRepositoryRootView(repositoryID: Binding<UUID?>) -> AnyView {
		repositoryDIContainer.makeRootView(repositoryID: repositoryID)
	}
}
