import DomainGitInterface
import Foundation

@MainActor
final class SavedRepositoryStoreSpy: SavedRepositoryStore {
	private(set) var repositories: [SavedRepository]
	private(set) var removedRepositoryIDs: [UUID] = []
	private(set) var selectedRepositoryID: UUID?
	private(set) var selectionRequestIDs: [UUID?] = []
	var selectionError: (any Error)?
	var removalError: (any Error)?
	var savedRepositoryOverride: SavedRepository?

	init(repositories: [SavedRepository]) {
		self.repositories = repositories
	}

	func requestRepositories() throws -> [SavedRepository] {
		repositories
	}

	func requestSaveRepository(at url: URL) throws -> SavedRepository {
		if let repository = savedRepositoryOverride {
			repositories = repositories.map { $0.id == repository.id ? repository : $0 }
			return repository
		}
		let repository = SavedRepository(
			id: UUID(),
			name: url.lastPathComponent,
			url: url,
			position: repositories.count,
			isSelected: false
		)
		repositories.append(repository)
		return repository
	}

	func requestRemoveRepository(id: UUID, selecting selectedRepositoryID: UUID?) throws {
		if let removalError { throw removalError }
		if let selectionError { throw selectionError }
		removedRepositoryIDs.append(id)
		repositories.removeAll { $0.id == id }
		try requestSelectRepository(id: selectedRepositoryID)
	}

	func requestSelectRepository(id: UUID?) throws {
		if let selectionError { throw selectionError }
		selectedRepositoryID = id
		selectionRequestIDs.append(id)
		repositories = repositories.map { repository in
			SavedRepository(
				id: repository.id,
				name: repository.name,
				url: repository.url,
				position: repository.position,
				isSelected: repository.id == id
			)
		}
	}
}
