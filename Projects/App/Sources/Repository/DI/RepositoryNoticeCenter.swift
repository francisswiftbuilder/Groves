import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class RepositoryNoticeCenter {
	public private(set) var notice: GitProcessNotice?

	public init() {}

	public nonisolated func post(_ notice: GitProcessNotice) {
		Task { @MainActor [weak self] in
			self?.notice = notice
		}
	}

	public func dismiss() {
		notice = nil
	}
}
