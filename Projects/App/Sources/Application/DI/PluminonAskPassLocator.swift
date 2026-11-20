import Foundation

enum PluminonAskPassLocator {
	static var bundledHelperURL: URL? {
		let url = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "PluminonAskPass.app", directoryHint: .isDirectory)
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "MacOS", directoryHint: .isDirectory)
			.appending(path: "PluminonAskPass")
		guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
		return url
	}
}
