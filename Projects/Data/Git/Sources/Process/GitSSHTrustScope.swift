import Foundation

struct GitSSHTrustScope: Sendable {
	private static let missingFileCodes: Set<CocoaError.Code> = [
		.fileReadNoSuchFile,
		.fileNoSuchFile,
	]

	let knownHostsURL: URL

	init(userKnownHostsURL: URL? = nil, fileManager: FileManager = .default) throws {
		let userKnownHostsURL =
			userKnownHostsURL
			?? fileManager.homeDirectoryForCurrentUser
			.appending(path: ".ssh/known_hosts", directoryHint: .notDirectory)
		knownHostsURL = fileManager.temporaryDirectory
			.appending(path: "GrovesKnownHosts-\(UUID().uuidString)", directoryHint: .notDirectory)
		let contents = try Self.contents(of: userKnownHostsURL)
		try contents.write(to: knownHostsURL, options: .atomic)
		do {
			try fileManager.setAttributes(
				[.posixPermissions: 0o600],
				ofItemAtPath: knownHostsURL.path
			)
		} catch {
			try? fileManager.removeItem(at: knownHostsURL)
			throw error
		}
	}

	private static func contents(of userKnownHostsURL: URL) throws -> Data {
		do {
			return try Data(contentsOf: userKnownHostsURL)
		} catch let error as CocoaError where Self.missingFileCodes.contains(error.code) {
			return Data()
		}
	}

	var sshOptions: [String] {
		let escapedPath = knownHostsURL.path.replacingOccurrences(of: "\"", with: "\\\"")
		return [
			"-o UserKnownHostsFile=\"\(escapedPath)\"",
			"-o StrictHostKeyChecking=ask",
		]
	}

	func remove(fileManager: FileManager = .default) {
		try? fileManager.removeItem(at: knownHostsURL)
	}
}
