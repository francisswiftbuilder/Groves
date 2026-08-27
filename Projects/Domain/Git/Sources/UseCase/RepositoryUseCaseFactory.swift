import DomainGitInterface
import Foundation

public enum RepositoryUseCaseFactory {
	@MainActor
	public static func makeTabsUseCase(
		repository: any GitRepository,
		savedRepositoryStore: any SavedRepositoryStore
	) -> any RepositoryTabsUseCase {
		DefaultRepositoryTabsUseCase(
			repository: repository,
			store: savedRepositoryStore
		)
	}

	public static func makeContentUseCase(
		repository: any GitRepository
	) -> any RepositoryContentUseCase {
		DefaultRepositoryContentUseCase(repository: repository)
	}

	public static func makeChangesUseCase(
		repository: any GitRepository
	) -> any RepositoryChangesUseCase {
		DefaultRepositoryChangesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeReferencesUseCase(
		repository: any GitRepository
	) -> any RepositoryReferencesUseCase {
		DefaultRepositoryReferencesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeStashesUseCase(
		repository: any GitRepository
	) -> any RepositoryStashesUseCase {
		DefaultRepositoryStashesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeOperationsUseCase(
		repository: any GitRepository
	) -> any RepositoryOperationsUseCase {
		DefaultRepositoryOperationsUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}
}
