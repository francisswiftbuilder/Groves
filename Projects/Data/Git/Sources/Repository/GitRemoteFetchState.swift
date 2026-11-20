import Foundation

actor GitRemoteFetchState {
	static let shared = GitRemoteFetchState()

	private var entries: [URL: [String: (url: String?, succeededAt: Date?, error: String?)]] = [:]

	func status(in repository: URL, remote: String, url: String?) -> (Date?, String?) {
		guard let entry = entries[repository]?[remote], entry.url == url else { return (nil, nil) }
		return (entry.succeededAt, entry.error)
	}

	func record(in repository: URL, remote: String, url: String?, error: String?) {
		let previous = status(in: repository, remote: remote, url: url).0
		entries[repository, default: [:]][remote] = (url, error == nil ? Date() : previous, error)
	}
}
