import Foundation

@MainActor
public protocol RepositoryExternalEditorOpening: AnyObject {
	func openFile(at fileURL: URL, applicationBundleIdentifier: String?) throws
}
