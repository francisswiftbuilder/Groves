import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class WorkspaceDiffPreferences: ObservableObject {
	@Published public var options = GitDiffOptions()
	@Published public var presentationMode: DiffPresentationMode = .unified

	public init() {}
}
