import DomainGitInterface
import Foundation

struct DefaultRepositoryReferencesUseCase: RepositoryReferencesUseCase {
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

	func createBranch(named name: String, from commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCreateBranch(
			named: name,
			from: commitHash,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func checkoutCommit(_ commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCheckoutCommit(commitHash, at: repositoryURL)
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

	func preparePull(at repositoryURL: URL) async throws -> RepositoryPullPreparation {
		let outcome = try await repository.requestPreparePull(at: repositoryURL)
		let snapshot = try await content.loadSnapshot(at: repositoryURL)
		return RepositoryPullPreparation(outcome: outcome, snapshot: snapshot)
	}

	func resolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestResolvePull(
			divergence,
			using: resolution,
			at: repositoryURL
		)
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
