import DomainGitInterface

@MainActor
final class RepositoryTab: Identifiable {
	nonisolated let id: SavedRepository.ID
	let repository: SavedRepository
	let workspace: RepositoryWorkspace
	var hasLoadedContent = false

	init(repository: SavedRepository, workspace: RepositoryWorkspace) {
		id = repository.id
		self.repository = repository
		self.workspace = workspace
	}
}
