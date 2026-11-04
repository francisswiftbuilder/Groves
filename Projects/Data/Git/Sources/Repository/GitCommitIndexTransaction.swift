import Darwin
import Foundation

final class GitCommitIndexTransaction {
	let temporaryIndexURL: URL
	private let lockURL: URL

	init(indexURL: URL) throws {
		lockURL = indexURL.appendingPathExtension("lock")
		temporaryIndexURL = indexURL.deletingLastPathComponent()
			.appending(path: "groves-commit-\(UUID().uuidString).index")
		let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		close(descriptor)
	}

	deinit {
		try? FileManager.default.removeItem(at: temporaryIndexURL.appendingPathExtension("lock"))
		try? FileManager.default.removeItem(at: temporaryIndexURL)
		try? FileManager.default.removeItem(at: lockURL)
	}
}
