import AppKit
import Foundation

@MainActor
protocol RepositoryWindowTabCoordinating: AnyObject, Sendable {
	func configure(_ window: NSWindow)
	func register(_ window: NSWindow)
	func openNewTab(repositoryID: UUID?, from existingWindow: NSWindow?)
}
