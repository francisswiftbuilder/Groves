import Foundation

public enum GitFileState: String, Sendable {
	case added
	case copied
	case deleted
	case ignored
	case modified
	case renamed
	case typeChanged
	case unmerged
	case untracked
	case unchanged

}

public struct WorkingTreeChange: Identifiable, Hashable, Sendable {
	public let path: String
	public let previousPath: String?
	public let indexState: GitFileState
	public let workingTreeState: GitFileState

	public var id: String { path }
	public var isStaged: Bool { indexState != .unchanged && indexState != .untracked }
	public var hasWorkingTreeChange: Bool { workingTreeState != .unchanged }

	public var displayState: GitFileState {
		hasWorkingTreeChange ? workingTreeState : indexState
	}

	public init(
		path: String,
		previousPath: String?,
		indexState: GitFileState,
		workingTreeState: GitFileState
	) {
		self.path = path
		self.previousPath = previousPath
		self.indexState = indexState
		self.workingTreeState = workingTreeState
	}
}

public struct GitAmendChange: Identifiable, Hashable, Sendable {
	public let path: String
	public let previousPath: String?
	public let state: GitFileState

	public var id: String { path }

	public init(path: String, previousPath: String?, state: GitFileState) {
		self.path = path
		self.previousPath = previousPath
		self.state = state
	}
}

public enum GitDiffLineAction: Equatable, Sendable {
	case stage
	case unstage
}

public struct GitDiffLineSelection: Hashable, Sendable {
	public let oldLineNumber: Int?
	public let newLineNumber: Int?

	public init(oldLineNumber: Int?, newLineNumber: Int?) {
		self.oldLineNumber = oldLineNumber
		self.newLineNumber = newLineNumber
	}
}

public struct GitCommit: Identifiable, Hashable, Sendable {
	public let hash: String
	public let shortHash: String
	public let parentHashes: [String]
	public let author: String
	public let date: Date
	public let references: [String]
	public let subject: String
	public let body: String

	public var id: String { hash }

	public init(
		hash: String,
		shortHash: String,
		parentHashes: [String],
		author: String,
		date: Date,
		references: [String],
		subject: String,
		body: String
	) {
		self.hash = hash
		self.shortHash = shortHash
		self.parentHashes = parentHashes
		self.author = author
		self.date = date
		self.references = references
		self.subject = subject
		self.body = body
	}
}

public struct GitBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let upstream: String?
	public let isCurrent: Bool

	public var id: String { name }

	public init(name: String, shortHash: String, upstream: String?, isCurrent: Bool) {
		self.name = name
		self.shortHash = shortHash
		self.upstream = upstream
		self.isCurrent = isCurrent
	}
}

public struct GitTag: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let date: Date?
	public let subject: String

	public var id: String { name }

	public init(name: String, shortHash: String, date: Date?, subject: String) {
		self.name = name
		self.shortHash = shortHash
		self.date = date
		self.subject = subject
	}
}

public struct RepositoryTreeNode: Identifiable, Hashable, Sendable {
	public let name: String
	public let path: String
	public let children: [RepositoryTreeNode]

	public var id: String { path }
	public var isDirectory: Bool { !children.isEmpty }

	public init(name: String, path: String, children: [RepositoryTreeNode]) {
		self.name = name
		self.path = path
		self.children = children
	}
}

public enum GitRepositoryError: LocalizedError, Sendable {
	case invalidRepository
	case commandFailed(String)
	case invalidOutput
	case invalidFilePath
	case fileUnavailable
	case fileTooLarge

	public var errorDescription: String? {
		switch self {
		case .invalidRepository:
			return "선택한 폴더는 Git 저장소가 아닙니다."
		case .commandFailed(let message):
			return message.isEmpty ? "Git 명령을 실행하지 못했습니다." : message
		case .invalidOutput:
			return "Git 출력 형식을 해석하지 못했습니다."
		case .invalidFilePath:
			return "저장소 밖의 파일은 열 수 없습니다."
		case .fileUnavailable:
			return "파일을 읽을 수 없습니다."
		case .fileTooLarge:
			return "미리보기에는 파일이 너무 큽니다."
		}
	}
}
