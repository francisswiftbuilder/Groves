import Foundation

enum GrovesAskPassLocator {
	static var bundledHelperURL: URL? {
		let url = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass")
		guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
		return url
	}
}
