import Foundation

enum GitWorktreeBranchUsage {
	static func directories(in commonDirectory: URL) throws -> [URL] {
		let worktrees = commonDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
		let linkedDirectories: [URL]
		do {
			linkedDirectories = try FileManager.default.contentsOfDirectory(
				at: worktrees, includingPropertiesForKeys: [.isDirectoryKey])
		} catch let error as CocoaError
			where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
		{
			linkedDirectories = []
		}
		return [commonDirectory]
			+ (try linkedDirectories.filter {
				try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
			}.sorted { $0.path < $1.path })
	}

	static func references(_ porcelain: String, in directories: [URL]) throws -> Set<String> {
		let branchPrefix = "branch "
		var references = Set(
			porcelain.split(separator: "\0").compactMap { field in
				field.hasPrefix(branchPrefix) ? String(field.dropFirst(branchPrefix.count)) : nil
			})
		for directory in directories {
			let rebase = try read("rebase-merge/head-name", in: directory)
			let apply = try read("rebase-apply/head-name", in: directory)
			if let head = rebase ?? apply, head.hasPrefix("refs/heads/") {
				references.insert(head)
			}
			if FileManager.default.fileExists(atPath: directory.appending(path: "BISECT_LOG").path),
				let branch = try read("BISECT_START", in: directory), !branch.isEmpty
			{
				references.insert(branch.hasPrefix("refs/heads/") ? branch : "refs/heads/\(branch)")
			}
			if let state = try read("rebase-merge/update-refs", in: directory) {
				let lines = state.split(whereSeparator: \.isNewline)
				for index in stride(from: 0, to: lines.count, by: 3) {
					references.insert(String(lines[index]))
				}
			}
		}
		return references
	}

	private static func read(_ path: String, in directory: URL) throws -> String? {
		do {
			return try String(contentsOf: directory.appending(path: path), encoding: .utf8)
				.trimmingCharacters(in: .newlines)
		} catch let error as CocoaError
			where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
		{
			return nil
		}
	}
}
