import DomainGitInterface
import FeatureRepositoryInterface
import Foundation

public struct ChangesDiffViewModelDependencies {
	public let changesUseCase: any RepositoryChangesUseCase
	public let preferences: WorkspaceDiffPreferences
	public let repositoryURL: @MainActor () -> URL?

	public init(
		changesUseCase: any RepositoryChangesUseCase,
		preferences: WorkspaceDiffPreferences,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.changesUseCase = changesUseCase
		self.preferences = preferences
		self.repositoryURL = repositoryURL
	}
}
