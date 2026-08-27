import DomainGitInterface
import Foundation

@MainActor
final class DefaultRepositoryTabsUseCase: RepositoryTabsUseCase {
	private let repository: any GitRepository
	private let store: any SavedRepositoryStore

	init(repository: any GitRepository, store: any SavedRepositoryStore) {
		self.repository = repository
		self.store = store
	}

	func loadTabs() throws -> RepositoryTabsSnapshot {
		var repositories = try store.requestRepositories()
		let selectedRepositoryID =
			repositories.first(where: { $0.isSelected })?.id ?? repositories.first?.id
		if repositories.contains(where: { $0.isSelected }) == false {
			try store.requestSelectRepository(id: selectedRepositoryID)
			repositories = try store.requestRepositories()
		}
		return RepositoryTabsSnapshot(
			repositories: repositories,
			selectedRepositoryID: selectedRepositoryID
		)
	}

	func openRepository(at url: URL) async throws -> SavedRepository {
		try await withSecurityScopedAccess(to: url) {
			let rootURL = try await repository.requestRepositoryRoot(at: url)
			return try saveAndSelectRepository(at: rootURL)
		}
	}

	func cloneRepository(from remoteURL: String, into directoryURL: URL) async throws
		-> SavedRepository
	{
		try await withSecurityScopedAccess(to: directoryURL) {
			let repositoryURL = try await repository.requestCloneRepository(
				from: remoteURL,
				into: directoryURL
			)
			return try saveAndSelectRepository(at: repositoryURL)
		}
	}

	func selectRepository(id: SavedRepository.ID) throws {
		guard try store.requestRepositories().contains(where: { $0.id == id }) else { return }
		try store.requestSelectRepository(id: id)
	}

	func removeRepository(id: SavedRepository.ID) throws -> RepositoryTabsSnapshot {
		let repositories = try store.requestRepositories()
		guard let removedIndex = repositories.firstIndex(where: { $0.id == id }) else {
			return try loadTabs()
		}
		let wasSelected = repositories[removedIndex].isSelected
		try store.requestRemoveRepository(id: id)
		let remainingRepositories = try store.requestRepositories()
		let selectedRepositoryID: SavedRepository.ID?
		if wasSelected {
			let nextIndex = min(removedIndex, remainingRepositories.count - 1)
			selectedRepositoryID = nextIndex >= 0 ? remainingRepositories[nextIndex].id : nil
			try store.requestSelectRepository(id: selectedRepositoryID)
		} else {
			selectedRepositoryID =
				remainingRepositories.first(where: { $0.isSelected })?.id
				?? remainingRepositories.first?.id
		}
		return RepositoryTabsSnapshot(
			repositories: try store.requestRepositories(),
			selectedRepositoryID: selectedRepositoryID
		)
	}

	private func saveAndSelectRepository(at url: URL) throws -> SavedRepository {
		let savedRepository = try store.requestSaveRepository(at: url)
		try store.requestSelectRepository(id: savedRepository.id)
		return savedRepository
	}

	private func withSecurityScopedAccess<Value>(
		to url: URL,
		operation: () async throws -> Value
	) async rethrows -> Value {
		let didAccessResource = url.startAccessingSecurityScopedResource()
		defer {
			if didAccessResource {
				url.stopAccessingSecurityScopedResource()
			}
		}
		return try await operation()
	}
}
