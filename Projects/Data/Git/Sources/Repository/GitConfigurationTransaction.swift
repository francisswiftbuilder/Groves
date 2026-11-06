import Darwin
import Foundation

final class GitConfigurationTransaction {
	let configurationURL: URL
	let stagingURL: URL
	private let lockURL: URL
	private var ownsLock = false
	private var ownsStagingFile = false

	init(configurationURL: URL) throws {
		self.configurationURL = configurationURL.resolvingSymlinksInPath()
		lockURL = self.configurationURL.appendingPathExtension("lock")
		stagingURL = self.configurationURL.deletingLastPathComponent()
			.appending(path: "groves-config-\(UUID().uuidString).config")
		let lockDescriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard lockDescriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		ownsLock = true
		close(lockDescriptor)
		let descriptor = open(stagingURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		ownsStagingFile = true
		let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		defer { try? handle.close() }
		do {
			try handle.write(contentsOf: Data(contentsOf: self.configurationURL))
			let attributes = try FileManager.default.attributesOfItem(atPath: self.configurationURL.path)
			if let permissions = attributes[.posixPermissions] {
				try FileManager.default.setAttributes(
					[.posixPermissions: permissions], ofItemAtPath: stagingURL.path)
			}
		} catch {
			removeStagingFiles()
			throw error
		}
	}

	deinit {
		removeStagingFiles()
	}

	func commit() throws {
		try Task.checkCancellation()
		guard ownsLock, ownsStagingFile else { throw POSIXError(.EINVAL) }
		guard rename(stagingURL.path, configurationURL.path) == 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		ownsStagingFile = false
	}

	private func removeStagingFiles() {
		guard ownsLock else { return }
		if ownsStagingFile {
			try? FileManager.default.removeItem(at: stagingURL.appendingPathExtension("lock"))
			try? FileManager.default.removeItem(at: stagingURL)
			ownsStagingFile = false
		}
		try? FileManager.default.removeItem(at: lockURL)
		ownsLock = false
	}
}
