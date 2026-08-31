import DomainGitInterface
import Foundation

struct WorkspaceViewModelActions {
	let resetContent: @MainActor () -> Void
	let distributeSnapshot: @MainActor (RepositorySnapshot, URL?, Bool) -> Void
	let refreshDiffPresentation: @MainActor () -> Void
	let focusConflict: @MainActor (GitConflict) async -> Void
	let activateSidebarSelection: @MainActor (RepositorySidebarSelection) -> Void
}
