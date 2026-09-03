import DomainGitInterface
import Foundation
import XCTest

@MainActor
final class SavedRepositoryStoreSpy: SavedRepositoryStore {
	private(set) var repositories: [SavedRepository]
	private(set) var removedRepositoryIDs: [UUID] = []
	private(set) var selectedRepositoryID: UUID?
	private(set) var selectionRequestIDs: [UUID?] = []

	init(repositories: [SavedRepository]) {
		self.repositories = repositories
	}

	func requestRepositories() throws -> [SavedRepository] {
		repositories
	}

	func requestSaveRepository(at url: URL) throws -> SavedRepository {
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

	func requestRemoveRepository(id: UUID) throws {
		removedRepositoryIDs.append(id)
		repositories.removeAll { $0.id == id }
	}

	func requestSelectRepository(id: UUID?) throws {
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
