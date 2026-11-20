import Darwin
import DomainGitInterface
import Foundation

final class GitWorktreeHeadLocks {
	private var paths: [URL] = []

	init(directories: [URL], reftable: Bool) throws {
		do {
			for directory in directories.dropFirst(reftable ? 1 : 0) {
				let path = directory.appending(path: reftable ? "reftable/tables.list.lock" : "HEAD.lock")
				let descriptor = open(path.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
				guard descriptor >= 0 else {
					throw GitRepositoryError.commandFailed(
						"Git is changing a worktree. Wait for it to finish and retry.")
				}
				close(descriptor)
				paths.append(path)
			}
		} catch {
			release()
			throw error
		}
	}

	deinit { release() }

	private func release() {
		for path in paths { try? FileManager.default.removeItem(at: path) }
		paths.removeAll()
	}
}
