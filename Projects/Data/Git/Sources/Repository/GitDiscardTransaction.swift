import Darwin
import DomainGitInterface
import Foundation

final class GitDiscardTransaction {
	let originalsURL: URL
	let replacementsURL: URL

	private let directoryURL: URL
	private let repositoryURL: URL
	private var capturedPaths: [String] = []

	init(repositoryURL: URL, gitDirectory: URL) throws {
		self.repositoryURL = repositoryURL
		let identifier = UUID().uuidString
		directoryURL = gitDirectory.appending(
			path: "groves-discard-\(identifier)", directoryHint: .isDirectory)
		originalsURL = directoryURL.appending(
			path: "Groves Discard \(identifier)", directoryHint: .isDirectory)
		replacementsURL = directoryURL.appending(path: "restore", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: directoryURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	}

	deinit {
		let disposableURL = capturedPaths.isEmpty ? directoryURL : replacementsURL
		try? FileManager.default.removeItem(at: disposableURL)
	}

	func capture(path: String) throws {
		let source = try workingTreeURL(for: path)
		let destination = originalsURL.appending(path: path)
		try prepareDirectory(for: destination)
		do {
			try moveExclusively(from: source, to: destination)
			capturedPaths.append(path)
		} catch let error as POSIXError where error.code == .ENOENT {
			return
		}
	}

	func removeEmptyDirectory(at path: String) throws {
		let destination = try workingTreeURL(for: path)
		_ = rmdir(destination.path)
	}

	func validateReplacementDestination(for path: String) throws {
		let destination = try workingTreeURL(for: path)
		var attributes = stat()
		if lstat(destination.path, &attributes) == 0 { throw replacementCollision(at: path) }
		if errno != ENOENT { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
	}

	func installReplacement(for path: String) throws {
		let destination = try workingTreeURL(for: path)
		try prepareDirectory(for: destination)
		do {
			try moveExclusively(from: replacementsURL.appending(path: path), to: destination)
		} catch let error as POSIXError where error.code == .EEXIST {
			throw replacementCollision(at: path)
		}
	}

	func rollback() -> Bool {
		capturedPaths = capturedPaths.reversed().filter { path in
			do {
				let destination = try workingTreeURL(for: path)
				try prepareDirectory(for: destination)
				try moveExclusively(from: originalsURL.appending(path: path), to: destination)
				return false
			} catch {
				return true
			}
		}
		return capturedPaths.isEmpty
	}

	func archiveOriginals(using archive: (URL) throws -> Void) throws {
		guard !capturedPaths.isEmpty else { return }
		try archive(originalsURL)
		capturedPaths = []
	}

	private func replacementCollision(at path: String) -> GitRepositoryError {
		.commandFailed(
			"A new file appeared at \(path) while replacing working files. That file was kept.")
	}

	private func workingTreeURL(for path: String) throws -> URL {
		let url = repositoryURL.appending(path: path).standardizedFileURL
		let parent = url.deletingLastPathComponent()
		guard url.path.hasPrefix(repositoryURL.path + "/"),
			parent.path == parent.resolvingSymlinksInPath().path
		else { throw GitRepositoryError.invalidFilePath }
		return url
	}

	private func prepareDirectory(for url: URL) throws {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	}

	private func moveExclusively(from source: URL, to destination: URL) throws {
		guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
	}
}
