import DomainGitInterface
import Foundation

@MainActor
public final class RepositoryNoticeCenter: ObservableObject {
	@Published public private(set) var notice: GitProcessNotice?

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
