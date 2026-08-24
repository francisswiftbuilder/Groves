import Foundation

public struct RepositoryTabsSnapshot: Equatable, Sendable {
	public let repositories: [SavedRepository]
	public let selectedRepositoryID: SavedRepository.ID?

	public init(
		repositories: [SavedRepository],
		selectedRepositoryID: SavedRepository.ID?
	) {
		self.repositories = repositories
		self.selectedRepositoryID = selectedRepositoryID
	}
}
