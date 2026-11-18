import DomainGitInterface
import Foundation

final class GitStashReflogTransaction {
	private let reference: GitCommitIndexTransaction
	private let reflog: GitCommitIndexTransaction
	private let packedReferences: GitCommitIndexTransaction
	private let referenceURL: URL
	private let reflogURL: URL
	private let packedReferencesURL: URL

	init(gitDirectory: URL) throws {
		referenceURL = gitDirectory.appending(path: "refs/stash")
		reflogURL = gitDirectory.appending(path: "logs/refs/stash")
		packedReferencesURL = gitDirectory.appending(path: "packed-refs")
		let manager = FileManager.default
		try manager.createDirectory(
			at: referenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try manager.createDirectory(
			at: reflogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		reference = try GitCommitIndexTransaction(indexURL: referenceURL)
		reflog = try GitCommitIndexTransaction(indexURL: reflogURL)
		packedReferences = try GitCommitIndexTransaction(indexURL: packedReferencesURL)
	}

	func drop(_ stash: GitStash) throws {
		let manager = FileManager.default
		let original = try Data(contentsOf: reflogURL)
		var entries = original.split(separator: 10).map { Data($0) }
		guard stash.reference.hasPrefix("stash@{"), stash.reference.hasSuffix("}"),
			let ordinal = Int(stash.reference.dropFirst(7).dropLast()),
			0..<entries.count ~= ordinal
		else { throw GitRepositoryError.invalidOutput }
		let removedIndex = entries.count - ordinal - 1
		let removed = try hashes(in: entries[removedIndex])
		guard String(decoding: removed.new, as: UTF8.self) == stash.hash else {
			throw GitRepositoryError.commandFailed("The stash list changed. Review the stash again.")
		}
		entries.remove(at: removedIndex)
		if entries.indices.contains(removedIndex) {
			entries[removedIndex].replaceSubrange(0..<removed.old.count, with: removed.old)
		}
		if let last = entries.last {
			let newReference = try hashes(in: last).new + Data([10])
			try newReference.write(to: reference.temporaryIndexURL)
		}
		try Data(entries.flatMap { $0 + Data([10]) }).write(to: reflog.temporaryIndexURL)
		if entries.isEmpty {
			try removePackedStashIfPresent()
			if manager.fileExists(atPath: referenceURL.path) { try manager.removeItem(at: referenceURL) }
			try manager.removeItem(at: reflogURL)
		} else {
			try reflog.installIndex()
			do {
				try reference.installIndex()
			} catch {
				try original.write(to: reflogURL, options: .atomic)
				throw error
			}
		}
	}

	private func hashes(in entry: Data) throws -> (old: Data, new: Data) {
		let fields = entry.split(separator: 32, maxSplits: 2)
		guard fields.count == 3, fields[0].count == fields[1].count,
			[40, 64].contains(fields[0].count)
		else { throw GitRepositoryError.invalidOutput }
		return (Data(fields[0]), Data(fields[1]))
	}

	private func removePackedStashIfPresent() throws {
		guard FileManager.default.fileExists(atPath: packedReferencesURL.path) else { return }
		let original = try Data(contentsOf: packedReferencesURL)
		let entries = original.split(separator: 10)
		let updated = entries.filter { !$0.suffix(11).elementsEqual(Data(" refs/stash".utf8)) }
		guard updated.count != entries.count else { return }
		try Data(updated.flatMap { $0 + Data([10]) }).write(to: packedReferences.temporaryIndexURL)
		try packedReferences.installIndex()
	}
}
