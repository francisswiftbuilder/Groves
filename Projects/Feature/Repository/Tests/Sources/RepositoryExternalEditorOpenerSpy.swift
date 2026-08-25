import FeatureRepositoryInterface
import Foundation

@MainActor
final class RepositoryExternalEditorOpenerSpy: RepositoryExternalEditorOpening {
	private(set) var openedFileURL: URL?
	private(set) var applicationBundleIdentifier: String?
	private(set) var invocationCount = 0
	var error: Error?

	func openFile(at fileURL: URL, applicationBundleIdentifier: String?) throws {
		invocationCount += 1
		if let error { throw error }
		openedFileURL = fileURL
		self.applicationBundleIdentifier = applicationBundleIdentifier
	}
}
