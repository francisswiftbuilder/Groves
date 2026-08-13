import Foundation

@MainActor
public protocol SavedRepositoryStore: AnyObject {
	func requestRepositories() throws -> [SavedRepository]
	func requestSaveRepository(at url: URL) throws -> SavedRepository
	func requestRemoveRepository(id: UUID) throws
	func requestSelectRepository(id: UUID?) throws
}
