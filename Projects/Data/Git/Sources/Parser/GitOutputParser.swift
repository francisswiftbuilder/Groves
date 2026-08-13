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
				let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(
					String.init)
				guard fields.count >= 7 else { return nil }
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
					subject: fields[6].trimmingCharacters(in: .newlines)
				)
			}
	}

	static func parseBranches(_ output: String) -> [GitBranch] {
		output.split(whereSeparator: \.isNewline).compactMap { line in
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard fields.count >= 4 else { return nil }
			return GitBranch(
				name: fields[0],
				shortHash: fields[1],
				upstream: fields[3].isEmpty ? nil : fields[3],
				isCurrent: fields[2] == "*"
			)
		}
	}

	static func parseTags(_ output: String) -> [GitTag] {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

		return output.split(whereSeparator: \.isNewline).compactMap { line in
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard fields.count >= 4 else { return nil }
			return GitTag(
				name: fields[0],
				shortHash: fields[1],
				date: formatter.date(from: fields[2]),
				subject: fields[3]
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

private struct MutableTreeNode {
	let name: String
	let path: String
	var children: [String: MutableTreeNode] = [:]

	mutating func insert(components: ArraySlice<String>, parentPath: String) {
		guard let name = components.first else { return }
		let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
		var child = children[name] ?? MutableTreeNode(name: name, path: path)
		child.insert(components: components.dropFirst(), parentPath: path)
		children[name] = child
	}
}

extension RepositoryTreeNode {
	fileprivate init(_ node: MutableTreeNode) {
		let children = node.children.values
			.map(RepositoryTreeNode.init)
			.sorted {
				if $0.isDirectory != $1.isDirectory {
					return $0.isDirectory
				}
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
		self.init(name: node.name, path: node.path, children: children)
	}
}
