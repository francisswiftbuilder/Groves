import Foundation

struct GitSSHTrustScope: Sendable {
	let knownHostsURL: URL

	init(userKnownHostsURL: URL? = nil, fileManager: FileManager = .default) throws {
		let userKnownHostsURL =
			userKnownHostsURL
			?? fileManager.homeDirectoryForCurrentUser
			.appending(path: ".ssh/known_hosts", directoryHint: .notDirectory)
		knownHostsURL = fileManager.temporaryDirectory
			.appending(path: "TreesKnownHosts-\(UUID().uuidString)", directoryHint: .notDirectory)
		let contents = (try? Data(contentsOf: userKnownHostsURL)) ?? Data()
		try contents.write(to: knownHostsURL, options: .atomic)
		try fileManager.setAttributes(
			[.posixPermissions: 0o600],
			ofItemAtPath: knownHostsURL.path
		)
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
