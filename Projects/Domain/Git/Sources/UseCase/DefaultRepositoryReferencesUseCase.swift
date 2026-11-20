import DomainGitInterface
import Foundation

public struct DefaultRepositoryReferencesUseCase: RepositoryReferencesUseCase {
	private let repository: any GitRepository
	private let content: any RepositoryContentUseCase

	public init(repository: any GitRepository, content: any RepositoryContentUseCase) {
		self.repository = repository
		self.content = content
	}

	public func pushAction(
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

	public func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestSwitchBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func createBranch(
		named name: String, from source: GitBranchCreationSource, checkout: Bool, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		try await repository.requestCreateBranch(
			named: name, from: source, checkout: checkout, at: repositoryURL)
		return await resultAfterMutation("Branch created.", at: repositoryURL)
	}

	public func checkoutCommit(_ commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCheckoutCommit(commitHash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func deleteBranches(
		localBranches: [GitBranch], remoteBranch: GitRemoteBranch?, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		var messages: [String] = []
		if let remoteBranch, !localBranches.isEmpty {
			try await repository.requestValidateRemoteBranchDeletion(remoteBranch, at: repositoryURL)
			let current = try await repository.requestBranches(at: repositoryURL)
			guard
				localBranches.allSatisfy({ branch in
					!current.contains { $0.name == branch.name }
						|| current.contains {
							$0.name == branch.name && $0.hash == branch.hash && $0.tracks(remoteBranch)
						}
				})
			else {
				throw GitRepositoryError.commandFailed(
					"The tracking branches changed. Review the deletion again.")
			}
		}
		if !localBranches.isEmpty {
			let outcome = try await repository.requestForceDeleteBranches(
				localBranches, at: repositoryURL)
			if case .deletedWithWarning(let message) = outcome { messages.append(message) }
		}
		if let remoteBranch {
			do {
				let outcome = try await repository.requestDeleteRemoteBranch(
					remoteBranch, at: repositoryURL)
				if case .deletedWithWarning(let message) = outcome { messages.append(message) }
			} catch {
				try Task.checkCancellation()
				guard !localBranches.isEmpty else { throw error }
				let names = localBranches.map { "“\($0.name)”" }.joined(separator: ", ")
				messages.append(
					"Deleted local branches \(names). The remote branch “\(remoteBranch.remoteDisplayName)” could not be deleted. \(error.localizedDescription)"
				)
			}
		}
		return await resultAfterMutation(
			"Branch deletion finished.", messages: messages, at: repositoryURL)
	}

	public func renameBranch(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestRenameBranch(named: name, to: newName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func mergeBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestMergeBranch(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func createTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		try await repository.requestCreateTag(
			named: name,
			message: message,
			commitHash: commitHash,
			at: repositoryURL
		)
		return await resultAfterMutation("Tag created.", at: repositoryURL)
	}

	public func deleteTag(_ tag: GitTag, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	{
		try await repository.requestDeleteTag(tag, at: repositoryURL)
		return await resultAfterMutation("Tag deleted.", at: repositoryURL)
	}

	public func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestFetch(remote: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestFetchAll(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func fetchAutomatically(at repositoryURL: URL) async throws {
		try await repository.requestFetchAll(at: repositoryURL, allowsUserInteraction: false)
	}

	public func preparePull(expecting branch: GitBranch, at repositoryURL: URL) async throws
		-> RepositoryPullPreparation
	{
		let outcome = try await repository.requestPreparePull(expecting: branch, at: repositoryURL)
		let snapshot = try await content.loadSnapshot(at: repositoryURL)
		return RepositoryPullPreparation(outcome: outcome, snapshot: snapshot)
	}

	public func resolvePull(
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

	public func push(
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
		return try await loadSnapshotAfterPush(at: repositoryURL)
	}

	public func forcePush(
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
		guard let currentBranch else { throw GitRepositoryError.invalidOutput }
		try await repository.requestForcePush(
			target, expecting: currentBranch, remotes: remotes, at: repositoryURL)
		return try await loadSnapshotAfterPush(at: repositoryURL)
	}

	public func pushTags(remote name: String, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	{
		let message = try await repository.requestPushTags(remote: name, at: repositoryURL)
		return await resultAfterMutation(
			"Tag push finished.", messages: [message].compactMap { $0 }, at: repositoryURL)
	}

	private func resultAfterMutation(
		_ completion: String, messages: [String] = [], at repositoryURL: URL
	)
		async -> RepositoryReferenceMutationResult
	{
		do {
			return RepositoryReferenceMutationResult(
				snapshot: try await content.loadSnapshot(at: repositoryURL),
				message: messages.isEmpty ? nil : messages.joined(separator: "\n\n"))
		} catch {
			let refresh =
				"\(completion) Pluminon couldn’t refresh the repository. \(error.localizedDescription)"
			return RepositoryReferenceMutationResult(
				snapshot: nil, message: (messages + [refresh]).joined(separator: "\n\n"))
		}
	}

	public func addRemote(
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

	public func renameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestRenameRemote(named: name, to: newName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func updateRemote(
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

	public func deleteRemote(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDeleteRemote(named: name, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	private func loadSnapshotAfterPush(at repositoryURL: URL) async throws -> RepositorySnapshot {
		do {
			return try await content.loadSnapshot(at: repositoryURL)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			throw GitRepositoryError.commandFailed(
				"Push succeeded, but Pluminon couldn’t refresh this repository.\n\n\(error.localizedDescription)"
			)
		}
	}

	private func pushTarget(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?
	) throws -> GitPushTarget {
		if let selectedRemoteName, !remotes.contains(where: { $0.name == selectedRemoteName }) {
			throw GitRepositoryError.commandFailed("The selected remote no longer exists.")
		}
		switch pushAction(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState
		) {
		case .unavailable:
			throw GitRepositoryError.commandFailed("푸시할 브랜치 또는 리모트가 없습니다.")
		case .upstream:
			return .upstream(branchName: currentBranch?.name, remoteName: selectedRemoteName)
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
