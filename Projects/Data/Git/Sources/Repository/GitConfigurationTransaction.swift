import Darwin
import Foundation

final class GitConfigurationTransaction {
	let configurationURL: URL
	let stagingURL: URL
	private var ownsLock = false

	init(configurationURL: URL) throws {
		self.configurationURL = configurationURL.resolvingSymlinksInPath()
		stagingURL = self.configurationURL.appendingPathExtension("lock")
		let descriptor = open(stagingURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		ownsLock = true
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
		guard ownsLock else { throw POSIXError(.EINVAL) }
		guard rename(stagingURL.path, configurationURL.path) == 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		ownsLock = false
	}

	private func removeStagingFiles() {
		guard ownsLock else { return }
		try? FileManager.default.removeItem(at: stagingURL.appendingPathExtension("lock"))
		try? FileManager.default.removeItem(at: stagingURL)
		ownsLock = false
	}
}
