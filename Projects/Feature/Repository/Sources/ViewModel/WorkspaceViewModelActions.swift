import DomainGitInterface
import Foundation

struct WorkspaceViewModelActions {
	let resetContent: @MainActor () -> Void
	let distributeSnapshot: @MainActor (RepositorySnapshot, URL?) -> Void
	let confirmRepositoryAction: @MainActor (PendingRepositoryConfirmation) -> Void
	let refreshDiffPresentation: @MainActor () -> Void
	let focusConflict: @MainActor (GitConflict) async -> Void
	let activateSidebarSelection: @MainActor (RepositorySidebarSelection) -> Void
}
