import DomainGitInterface
import Foundation

final class GitProcessNoticeRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var recordedNotices: [GitProcessNotice] = []

	var notices: [GitProcessNotice] {
		lock.withLock { recordedNotices }
	}

	func record(_ notice: GitProcessNotice) {
		lock.withLock { recordedNotices.append(notice) }
	}
}
