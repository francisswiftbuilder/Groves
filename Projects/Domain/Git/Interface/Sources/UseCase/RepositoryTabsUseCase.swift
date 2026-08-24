import Foundation

@MainActor
public protocol RepositoryTabsUseCase: AnyObject {
	func loadTabs() throws -> RepositoryTabsSnapshot
	func openRepository(at url: URL) async throws -> SavedRepository
	func cloneRepository(from remoteURL: String, into directoryURL: URL) async throws
		-> SavedRepository
	func selectRepository(id: SavedRepository.ID) throws
	func removeRepository(id: SavedRepository.ID) throws -> RepositoryTabsSnapshot
}
