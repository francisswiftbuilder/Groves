import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceDiffPreferences {
	public var options = GitDiffOptions()
	public var presentationMode: DiffPresentationMode = .unified

	public init() {}
}
