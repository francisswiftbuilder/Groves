import AppKit
import FeatureRepositoryInterface

@MainActor
final class WorkspaceExternalEditorOpener: RepositoryExternalEditorOpening {
	func openFile(at fileURL: URL, applicationBundleIdentifier: String?) throws {
		if let applicationBundleIdentifier {
			guard
				let applicationURL = NSWorkspace.shared.urlForApplication(
					withBundleIdentifier: applicationBundleIdentifier
				)
			else {
				throw CocoaError(.fileNoSuchFile)
			}
			let configuration = NSWorkspace.OpenConfiguration()
			NSWorkspace.shared.open(
				[fileURL],
				withApplicationAt: applicationURL,
				configuration: configuration
			)
		} else {
			NSWorkspace.shared.open(fileURL)
		}
	}
}
