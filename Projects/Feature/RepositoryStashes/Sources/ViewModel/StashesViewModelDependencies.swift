import CoreRepositoryDiff
import DomainGitInterface
import Foundation

public struct StashesViewModelDependencies {
	public let useCase: any RepositoryStashesUseCase
	public let preferences: WorkspaceDiffPreferences
	public let repositoryURL: @MainActor () -> URL?

	public init(
		useCase: any RepositoryStashesUseCase,
		preferences: WorkspaceDiffPreferences,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.useCase = useCase
		self.preferences = preferences
		self.repositoryURL = repositoryURL
	}
}
