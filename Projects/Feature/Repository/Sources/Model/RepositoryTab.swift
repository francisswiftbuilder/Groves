import DomainGitInterface

@MainActor
final class RepositoryTab: Identifiable {
	nonisolated let id: SavedRepository.ID
	let repository: SavedRepository
	let workspace: WorkspaceViewModel
	var hasLoadedContent = false

	init(repository: SavedRepository, workspace: WorkspaceViewModel) {
		id = repository.id
		self.repository = repository
		self.workspace = workspace
	}
}
