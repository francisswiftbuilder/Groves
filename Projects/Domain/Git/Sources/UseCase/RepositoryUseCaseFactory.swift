import DomainGitInterface
import Foundation

public enum RepositoryUseCaseFactory {
	@MainActor
	public static func makeTabsUseCase(
		repository: any GitRepository,
		savedRepositoryStore: any SavedRepositoryStore
	) -> any RepositoryTabsUseCase {
		DefaultRepositoryTabsUseCase(
			repository: repository,
			store: savedRepositoryStore
		)
	}

	public static func makeContentUseCase(
		repository: any GitRepository
	) -> any RepositoryContentUseCase {
		DefaultRepositoryContentUseCase(repository: repository)
	}

	public static func makeChangesUseCase(
		repository: any GitRepository
	) -> any RepositoryChangesUseCase {
		DefaultRepositoryChangesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeReferencesUseCase(
		repository: any GitRepository
	) -> any RepositoryReferencesUseCase {
		DefaultRepositoryReferencesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeStashesUseCase(
		repository: any GitRepository
	) -> any RepositoryStashesUseCase {
		DefaultRepositoryStashesUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}

	public static func makeOperationsUseCase(
		repository: any GitRepository
	) -> any RepositoryOperationsUseCase {
		DefaultRepositoryOperationsUseCase(
			repository: repository,
			content: DefaultRepositoryContentUseCase(repository: repository)
		)
	}
}

@MainActor
private final class DefaultRepositoryTabsUseCase: RepositoryTabsUseCase {
	private let repository: any GitRepository
	private let store: any SavedRepositoryStore

	init(repository: any GitRepository, store: any SavedRepositoryStore) {
		self.repository = repository
		self.store = store
	}

	func loadTabs() throws -> RepositoryTabsSnapshot {
		var repositories = try store.requestRepositories()
		let selectedRepositoryID =
			repositories.first(where: { $0.isSelected })?.id ?? repositories.first?.id
		if repositories.contains(where: { $0.isSelected }) == false {
			try store.requestSelectRepository(id: selectedRepositoryID)
			repositories = try store.requestRepositories()
		}
		return RepositoryTabsSnapshot(
			repositories: repositories,
			selectedRepositoryID: selectedRepositoryID
		)
	}

	func openRepository(at url: URL) async throws -> SavedRepository {
		try await withSecurityScopedAccess(to: url) {
			let rootURL = try await repository.requestRepositoryRoot(at: url)
			return try saveAndSelectRepository(at: rootURL)
		}
	}

	func cloneRepository(from remoteURL: String, into directoryURL: URL) async throws
		-> SavedRepository
	{
		try await withSecurityScopedAccess(to: directoryURL) {
			let repositoryURL = try await repository.requestCloneRepository(
				from: remoteURL,
				into: directoryURL
			)
			return try saveAndSelectRepository(at: repositoryURL)
		}
	}

	func selectRepository(id: SavedRepository.ID) throws {
		guard try store.requestRepositories().contains(where: { $0.id == id }) else { return }
		try store.requestSelectRepository(id: id)
	}

	func removeRepository(id: SavedRepository.ID) throws -> RepositoryTabsSnapshot {
		let repositories = try store.requestRepositories()
		guard let removedIndex = repositories.firstIndex(where: { $0.id == id }) else {
			return try loadTabs()
		}
		let wasSelected = repositories[removedIndex].isSelected
		try store.requestRemoveRepository(id: id)
		let remainingRepositories = try store.requestRepositories()
		let selectedRepositoryID: SavedRepository.ID?
		if wasSelected {
			let nextIndex = min(removedIndex, remainingRepositories.count - 1)
			selectedRepositoryID = nextIndex >= 0 ? remainingRepositories[nextIndex].id : nil
			try store.requestSelectRepository(id: selectedRepositoryID)
		} else {
			selectedRepositoryID =
				remainingRepositories.first(where: { $0.isSelected })?.id
				?? remainingRepositories.first?.id
		}
		return RepositoryTabsSnapshot(
			repositories: try store.requestRepositories(),
			selectedRepositoryID: selectedRepositoryID
		)
	}

	private func saveAndSelectRepository(at url: URL) throws -> SavedRepository {
		let savedRepository = try store.requestSaveRepository(at: url)
		try store.requestSelectRepository(id: savedRepository.id)
		return savedRepository
	}

	private func withSecurityScopedAccess<Value>(
		to url: URL,
		operation: () async throws -> Value
	) async rethrows -> Value {
		let didAccessResource = url.startAccessingSecurityScopedResource()
		defer {
			if didAccessResource {
				url.stopAccessingSecurityScopedResource()
			}
		}
		return try await operation()
	}
}

private struct DefaultRepositoryContentUseCase: RepositoryContentUseCase {
	let repository: any GitRepository

	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot {
		async let changes = repository.requestWorkingTreeChanges(at: repositoryURL)
		async let amendChanges = repository.requestAmendChanges(at: repositoryURL)
		async let commits = repository.requestCommitHistory(at: repositoryURL)
		async let branches = repository.requestBranches(at: repositoryURL)
		async let remotes = repository.requestRemotes(at: repositoryURL)
		async let operationState = repository.requestOperationState(at: repositoryURL)
		async let tags = repository.requestTags(at: repositoryURL)
		async let stashes = repository.requestStashes(at: repositoryURL)
		async let fileTree = repository.requestFileTree(at: repositoryURL)

		return try await RepositorySnapshot(
			changes: changes,
			amendChanges: amendChanges,
			commits: commits,
			branches: branches,
			remotes: remotes,
			operationState: operationState,
			tags: tags,
			stashes: stashes,
			fileTree: fileTree
		)
	}

	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
		try await repository.requestFileContents(at: path, in: repositoryURL)
	}
}

private struct DefaultRepositoryChangesUseCase: RepositoryChangesUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> String {
		try await repository.requestDiff(for: change, source: source, at: repositoryURL)
	}

	func loadAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		try await repository.requestAmendDiff(for: change, at: repositoryURL)
	}

	func loadCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String {
		try await repository.requestCommitDiff(for: commit, at: repositoryURL)
	}

	func stage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.hasWorkingTreeChange {
			try await repository.requestStage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func unstage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.isStaged {
			try await repository.requestUnstage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func unstageFromAmend(_ changes: [GitAmendChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func applyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		try await repository.requestApplyDiffLine(
			selection,
			action: action,
			for: change,
			at: repositoryURL
		)
		return try await repository.requestWorkingTreeChanges(at: repositoryURL)
	}

	func discard(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestDiscard(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func commit(subject: String, body: String, amend: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCommit(
			subject: subject,
			body: body,
			amend: amend,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func amendWithoutEditingMessage(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestAmendWithoutEditingMessage(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}

private struct DefaultRepositoryReferencesUseCase: RepositoryReferencesUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func pushAction(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState
	) -> RepositoryPushAction {
		guard let currentBranch, !operationState.isDetached, operationState.isIdle else {
			return .unavailable
		}
		if currentBranch.upstream != nil {
			return .upstream
		}
		let remoteNames = remotes.map(\.name)
		switch remoteNames.count {
		case 0:
			return .unavailable
		case 1:
			return .setUpstream(remoteName: remoteNames[0], branchName: currentBranch.name)
		default:
			return .chooseRemote(remoteNames: remoteNames, branchName: currentBranch.name)
		}
	}

	func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestSwitchBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func createBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCreateBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func createTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestCreateTrackingBranch(
			named: name,
			tracking: remoteBranch,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func renameBranch(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestRenameBranch(named: name, to: newName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func mergeBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestMergeBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func createTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestCreateTag(
			named: name,
			message: message,
			commitHash: commitHash,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func deleteTag(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteTag(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestFetch(remote: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestFetchAll(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func pull(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestPull(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func push(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		let target = try pushTarget(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState,
			selectedRemoteName: selectedRemoteName
		)
		try await repository.requestPush(target, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func forcePush(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		let target = try pushTarget(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState,
			selectedRemoteName: selectedRemoteName
		)
		try await repository.requestForcePush(target, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func pushTags(remote name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestPushTags(remote: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func addRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestAddRemote(
			named: name,
			fetchURL: fetchURL,
			pushURL: pushURL,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func renameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestRenameRemote(named: name, to: newName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func updateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestUpdateRemote(
			named: name,
			fetchURL: fetchURL,
			pushURL: pushURL,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func deleteRemote(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteRemote(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func deleteRemoteBranch(_ branch: GitRemoteBranch, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteRemoteBranch(branch, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	private func pushTarget(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?
	) throws -> GitPushTarget {
		switch pushAction(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState
		) {
		case .unavailable:
			throw GitRepositoryError.commandFailed("푸시할 브랜치 또는 리모트가 없습니다.")
		case .upstream:
			return .upstream
		case .setUpstream(let remoteName, let branchName):
			return .setUpstream(remoteName: remoteName, branchName: branchName)
		case .chooseRemote(let remoteNames, let branchName):
			guard let selectedRemoteName, remoteNames.contains(selectedRemoteName) else {
				throw GitRepositoryError.commandFailed("푸시할 리모트를 선택해 주세요.")
			}
			return .setUpstream(
				remoteName: selectedRemoteName,
				branchName: branchName
			)
		}
	}
}

private struct DefaultRepositoryStashesUseCase: RepositoryStashesUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func loadDiff(for stash: GitStash, at repositoryURL: URL) async throws -> String {
		try await repository.requestStashDiff(for: stash, at: repositoryURL)
	}

	func createStash(message: String, includeUntracked: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCreateStash(
			message: message,
			includeUntracked: includeUntracked,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestApplyStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestPopStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDropStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
