import AppKit
import Foundation

@MainActor
protocol RepositoryWindowTabCoordinating: AnyObject, Sendable {
	func configure(_ window: NSWindow)
	func register(_ window: NSWindow, repositoryID: UUID?)
	func openNewTab(repositoryID: UUID?, from existingWindow: NSWindow?)
	func restoreRepositoryWindows(_ restoration: RepositoryWindowRestoration)
	func prepareForTermination()
}
