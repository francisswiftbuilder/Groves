import Combine
import DomainGitInterface
import Foundation

@MainActor
final class WorkspaceDiffPreferences: ObservableObject {
	@Published var options = GitDiffOptions()
	@Published var presentationMode: DiffPresentationMode = .unified
}
