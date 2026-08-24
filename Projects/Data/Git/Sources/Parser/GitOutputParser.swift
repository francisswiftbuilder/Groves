import DomainGitInterface
import Foundation

enum GitOutputParser {
	static func parseWorkingTreeChanges(_ output: String) -> [WorkingTreeChange] {
		let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
		var changes: [WorkingTreeChange] = []
		var index = 0

		while index < records.count {
			let record = records[index]
			guard record.count >= 4 else {
				index += 1
				continue
			}

			let status = Array(record.prefix(2))
			let path = String(record.dropFirst(3))
			let indexState = parseFileState(status[0])
			let workingTreeState = parseFileState(status[1])
			let isRenameOrCopy =
				status[0] == "R" || status[0] == "C" || status[1] == "R" || status[1] == "C"
			var previousPath: String?

			if isRenameOrCopy, index + 1 < records.count {
				previousPath = records[index + 1]
				index += 1
			}

			changes.append(
				WorkingTreeChange(
					path: path,
					previousPath: previousPath,
					indexState: indexState,
					workingTreeState: workingTreeState
				)
			)
			index += 1
		}

		return mergeWorkingTreeChanges(changes)
	}

	static func parseAmendChanges(_ output: String) -> [GitAmendChange] {
		let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
		var changes: [GitAmendChange] = []
		var index = 0

		while index < records.count {
			let status = records[index]
			index += 1
			guard let statusCharacter = status.first, index < records.count else { continue }

			let state = parseFileState(statusCharacter)
			let isRenameOrCopy = statusCharacter == "R" || statusCharacter == "C"
			let previousPath: String?
			let path: String

			if isRenameOrCopy, index + 1 < records.count {
				previousPath = records[index]
				path = records[index + 1]
				index += 2
			} else {
				previousPath = nil
				path = records[index]
				index += 1
			}

			changes.append(
				GitAmendChange(path: path, previousPath: previousPath, state: state)
			)
		}

		return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
	}

	static func parseCommits(_ output: String) -> [GitCommit] {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let fallbackFormatter = ISO8601DateFormatter()

		return
			output
			.split(separator: "\u{1e}", omittingEmptySubsequences: true)
			.compactMap { record in
				let fields = record.split(
					separator: "\u{1f}",
					maxSplits: 7,
					omittingEmptySubsequences: false
				).map(String.init)
				guard fields.count >= 8 else { return nil }
				guard let date = formatter.date(from: fields[4]) ?? fallbackFormatter.date(from: fields[4])
				else {
					return nil
				}

				let references = fields[5]
					.split(separator: ",")
					.map { $0.trimmingCharacters(in: .whitespaces) }
					.filter { !$0.isEmpty }

				return GitCommit(
					hash: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
					shortHash: fields[1],
					parentHashes: fields[2].split(separator: " ").map(String.init),
					author: fields[3],
					date: date,
					references: references,
					subject: fields[6].trimmingCharacters(in: .newlines),
					body: fields[7].trimmingCharacters(in: .newlines)
				)
			}
	}

	static func parseBranches(_ output: String) -> [GitBranch] {
		output.split(whereSeparator: \.isNewline).compactMap { line in
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard fields.count >= 5 else { return nil }
			let trackingCounts = parseTrackingCounts(fields[4])
			return GitBranch(
				name: fields[0],
				shortHash: fields[1],
				upstream: fields[3].isEmpty ? nil : fields[3],
				aheadCount: trackingCounts.ahead,
				behindCount: trackingCounts.behind,
				isCurrent: fields[2] == "*"
			)
		}
	}

	private static func parseTrackingCounts(_ value: String) -> (ahead: Int, behind: Int) {
		var ahead = 0
		var behind = 0

		for component in value.split(separator: ",") {
			let fields = component.split(whereSeparator: \.isWhitespace)
			guard fields.count == 2, let count = Int(fields[1]) else { continue }
			switch fields[0] {
			case "ahead":
				ahead = count
			case "behind":
				behind = count
			default:
				continue
			}
		}

		return (ahead, behind)
	}

	static func parseRemotes(_ output: String) -> [GitRemote] {
		var remoteOrder: [String] = []
		var remoteURLs: [String: (fetch: String?, push: String?)] = [:]

		for line in output.split(whereSeparator: \.isNewline) {
			let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
			guard fields.count == 2 else { continue }
			let name = fields[0]
			let value = fields[1]
			guard let markerRange = value.range(of: " (", options: .backwards) else { continue }
			let url = String(value[..<markerRange.lowerBound])
			let kind = String(value[markerRange.lowerBound...])

			if remoteURLs[name] == nil {
				remoteOrder.append(name)
				remoteURLs[name] = (nil, nil)
			}
			if kind == " (fetch)" {
				remoteURLs[name]?.fetch = url
			} else if kind == " (push)" {
				remoteURLs[name]?.push = url
			}
		}

		return remoteOrder.compactMap { name in
			guard let urls = remoteURLs[name] else { return nil }
			return GitRemote(name: name, fetchURL: urls.fetch, pushURL: urls.push)
		}
	}

	static func parseRemoteBranches(_ output: String) -> [GitRemoteBranch] {
		output.split(whereSeparator: \.isNewline).compactMap { line in
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard fields.count >= 4, fields[3].isEmpty else { return nil }
			let fullName = fields[0]
			guard let separatorIndex = fullName.firstIndex(of: "/") else { return nil }
			let remoteName = String(fullName[..<separatorIndex])
			let branchName = String(fullName[fullName.index(after: separatorIndex)...])
			guard !remoteName.isEmpty, !branchName.isEmpty else { return nil }

			return GitRemoteBranch(
				name: branchName,
				fullName: fullName,
				remoteName: remoteName,
				shortHash: fields[1],
				hash: fields[2]
			)
		}
	}

	static func parseTags(_ output: String) -> [GitTag] {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

		return output.split(whereSeparator: \.isNewline).compactMap { line in
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard fields.count >= 6 else { return nil }
			let targetHash = fields[2].isEmpty ? fields[3] : fields[2]
			return GitTag(
				name: fields[0],
				shortHash: fields[1],
				targetHash: targetHash,
				date: formatter.date(from: fields[4]),
				subject: fields[5]
			)
		}
	}

	static func parseStashes(_ output: String) -> [GitStash] {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

		return
			output
			.split(separator: "\u{1e}", omittingEmptySubsequences: true)
			.compactMap { record in
				let fields = record.split(
					separator: "\u{1f}",
					maxSplits: 3,
					omittingEmptySubsequences: false
				).map(String.init)
				guard fields.count == 4 else { return nil }
				return GitStash(
					reference: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
					hash: fields[1],
					subject: fields[2],
					date: formatter.date(from: fields[3].trimmingCharacters(in: .newlines))
				)
			}
	}

	static func buildFileTree(paths: [String]) -> [RepositoryTreeNode] {
		var root = MutableTreeNode(name: "", path: "")

		for path in paths where !path.isEmpty {
			let components = path.split(separator: "/").map(String.init)
			root.insert(components: ArraySlice(components), parentPath: "")
		}

		return root.children.values
			.map(RepositoryTreeNode.init)
			.sorted { treeSort($0, $1) == .orderedAscending }
	}

	private static func parseFileState(_ character: Character) -> GitFileState {
		switch character {
		case "A":
			return .added
		case "C":
			return .copied
		case "D":
			return .deleted
		case "!":
			return .ignored
		case "M":
			return .modified
		case "R":
			return .renamed
		case "T":
			return .typeChanged
		case "U":
			return .unmerged
		case "?":
			return .untracked
		default:
			return .unchanged
		}
	}

	private static func mergeWorkingTreeChanges(
		_ changes: [WorkingTreeChange]
	) -> [WorkingTreeChange] {
		var changesByPath: [String: WorkingTreeChange] = [:]

		for change in changes {
			guard let existingChange = changesByPath[change.path] else {
				changesByPath[change.path] = change
				continue
			}

			changesByPath[change.path] = WorkingTreeChange(
				path: change.path,
				previousPath: existingChange.previousPath ?? change.previousPath,
				indexState: mergeFileState(existingChange.indexState, change.indexState),
				workingTreeState: mergeFileState(
					existingChange.workingTreeState,
					change.workingTreeState
				)
			)
		}

		return changesByPath.values.sorted {
			$0.path.localizedStandardCompare($1.path) == .orderedAscending
		}
	}

	private static func mergeFileState(
		_ lhs: GitFileState,
		_ rhs: GitFileState
	) -> GitFileState {
		let states = [lhs, rhs]
		return states.first { $0 != .unchanged && $0 != .untracked }
			?? states.first { $0 == .untracked }
			?? .unchanged
	}

	private static func treeSort(
		_ lhs: RepositoryTreeNode,
		_ rhs: RepositoryTreeNode
	) -> ComparisonResult {
		if lhs.isDirectory != rhs.isDirectory {
			return lhs.isDirectory ? .orderedAscending : .orderedDescending
		}
		return lhs.name.localizedStandardCompare(rhs.name)
	}
}
