import Foundation

@MainActor
public protocol RepositoryFindActions: AnyObject {
	func present()
	func next()
	func previous()
}
