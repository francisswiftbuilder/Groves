import Combine
import DomainGitInterface
import Foundation

@MainActor
final class RepositoryOperationViewModel: ObservableObject {
	@Published var selectedBranchID: String?
	@Published var selectedRemoteID: String?
	@Published var pendingPullDivergence: RepositoryPullDivergence?
	@Published private(set) var branches: [GitBranch] = []
	@Published private(set) var remotes: [GitRemote] = []
	@Published private(set) var tags: [GitTag] = []
	@Published private(set) var operationState: RepositoryOperationState = .normal
	@Published private(set) var isLoading = false
	@Published var newBranchName = ""
	@Published var isPresentingNewBranch = false
	@Published private(set) var pendingBranchStartCommit: GitCommit?
	@Published var branchRenameName = ""
	@Published var pendingBranchRename: GitBranch?
	@Published var newTagName = ""
	@Published var newTagMessage = ""
	@Published private(set) var pendingTagCommit: GitCommit?
	@Published var pendingMainlineAction: PendingMainlineAction?
	@Published var pendingResetCommit: GitCommit?
	@Published var resetMode: GitResetMode = .mixed
	@Published var remoteEditorPresentation: RemoteEditorPresentation?
	@Published var pendingRemoteRename: GitRemote?

	private let dependencies: RepositoryOperationViewModelDependencies
	private let actions: RepositoryOperationViewModelActions
	private var changes: [WorkingTreeChange] = []
	private var mutationTask: Task<Void, Never>?
	private var networkTask: Task<Void, Never>?

	init(
		dependencies: RepositoryOperationViewModelDependencies,
		actions: RepositoryOperationViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	private var contentUseCase: any RepositoryContentUseCase {
		dependencies.contentUseCase
	}

	private var referencesUseCase: any RepositoryReferencesUseCase {
		dependencies.referencesUseCase
	}

	private var operationsUseCase: (any RepositoryOperationsUseCase)? {
		dependencies.operationsUseCase
	}

	private var repositoryURL: @MainActor () -> URL? {
		dependencies.repositoryURL
	}

	private var didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void {
		actions.didProduceSnapshot
	}

	private var didReceiveError: @MainActor (String) -> Void {
		actions.didReceiveError
	}

	private var didRequestConfirmation: @MainActor (PendingRepositoryConfirmation) -> Void {
		actions.didRequestConfirmation
	}

	private var didRequestViewConflicts: @MainActor (GitConflict) -> Void {
		actions.didRequestViewConflicts
	}

	deinit {
		mutationTask?.cancel()
		networkTask?.cancel()
	}

	var currentBranch: GitBranch? {
		branches.first(where: \.isCurrent)
	}

	var currentBranchName: String {
		guard !operationState.isDetached else { return "Detached HEAD" }
		return currentBranch?.name ?? "No Branch"
	}

	var currentBranchStatus: String {
		guard let currentBranch else { return operationStateTitle }
		var components = [currentBranch.name]
		if let upstream = currentBranch.upstream {
			components.append(upstream)
		}
		if currentBranch.aheadCount > 0 {
			components.append("↑\(currentBranch.aheadCount)")
		}
		if currentBranch.behindCount > 0 {
			components.append("↓\(currentBranch.behindCount)")
		}
		if !operationState.isIdle || operationState.isDetached {
			components.append(operationStateTitle)
		}
		return components.joined(separator: " · ")
	}

	var selectedBranch: GitBranch? {
		branches.first { $0.id == selectedBranchID }
	}

	var selectedRemote: GitRemote? {
		remotes.first { $0.id == selectedRemoteID }
	}

	var remoteBranches: [GitRemoteBranch] {
		remotes.flatMap(\.branches)
	}

	var conflicts: [GitConflict] {
		operationState.conflicts
	}

	var pushAction: RepositoryPushAction {
		referencesUseCase.pushAction(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState
		)
	}

	var forcePushConfirmationTitle: String {
		"Force Push \(currentBranchName)?"
	}

	var canCheckoutCommit: Bool {
		operationState.isIdle && changes.isEmpty && !isLoading
	}

	func canMergeBranch(_ branch: GitBranch) -> Bool {
		currentBranch != nil
			&& !branch.isCurrent
			&& operationState.isIdle
			&& !operationState.isDetached
			&& !isLoading
	}

	func canRebaseOnto(_ branch: GitBranch) -> Bool {
		canMergeBranch(branch) && changes.isEmpty
	}

	func apply(_ snapshot: RepositorySnapshot) {
		branches = snapshot.branches
		remotes = snapshot.remotes
		tags = snapshot.tags
		operationState = snapshot.operationState
		changes = snapshot.changes
		preserveSelection()
	}

	func reset() {
		cancelTasks()
		selectedBranchID = nil
		selectedRemoteID = nil
		pendingPullDivergence = nil
		branches = []
		remotes = []
		tags = []
		changes = []
		operationState = .normal
	}

	func cancelTasks() {
		mutationTask?.cancel()
		networkTask?.cancel()
	}

	func didPresentNewBranch(from commit: GitCommit? = nil) {
		newBranchName = ""
		pendingBranchStartCommit = commit
		isPresentingNewBranch = true
	}

	func didDismissNewBranch() {
		newBranchName = ""
		pendingBranchStartCommit = nil
		isPresentingNewBranch = false
	}

	func didRequestCreateBranch() {
		guard let repositoryURL = repositoryURL(), operationState.isIdle else { return }
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		let startCommit = pendingBranchStartCommit
		requestMutation {
			let snapshot: RepositorySnapshot
			if let startCommit {
				snapshot = try await self.referencesUseCase.createBranch(
					named: name,
					from: startCommit.hash,
					at: repositoryURL
				)
			} else {
				snapshot = try await self.referencesUseCase.createBranch(
					named: name,
					at: repositoryURL
				)
			}
			self.didDismissNewBranch()
			return snapshot
		}
	}

	func didPresentNewTag(for commit: GitCommit) {
		newTagName = ""
		newTagMessage = ""
		pendingTagCommit = commit
	}

	func didDismissNewTag() {
		newTagName = ""
		newTagMessage = ""
		pendingTagCommit = nil
	}

	func didRequestCreateTag() {
		guard let repositoryURL = repositoryURL(), let commit = pendingTagCommit else { return }
		let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
		let message = newTagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		requestMutation {
			let snapshot = try await self.referencesUseCase.createTag(
				named: name,
				message: message,
				commitHash: commit.hash,
				at: repositoryURL
			)
			self.didDismissNewTag()
			return snapshot
		}
	}

	func didPresentTagDeletion(_ tag: GitTag) {
		didRequestConfirmation(.deleteTag(tag))
	}

	func didRequestSwitchBranch() {
		guard let branch = selectedBranch else { return }
		didRequestSwitchBranch(branch)
	}

	func didRequestSwitchBranch(_ branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), !branch.isCurrent, operationState.isIdle else {
			return
		}
		requestMutation {
			try await self.referencesUseCase.switchBranch(named: branch.name, at: repositoryURL)
		}
	}

	func didPresentCheckoutCommit(_ commit: GitCommit) {
		guard operationState.isIdle, changes.isEmpty, !isLoading else { return }
		didRequestConfirmation(.checkoutCommit(commit))
	}

	func didRequestCreateLocalBranch(from remoteBranch: GitRemoteBranch) {
		guard
			let repositoryURL = repositoryURL(),
			!branches.contains(where: { $0.name == remoteBranch.name }),
			operationState.isIdle
		else { return }
		requestMutation {
			try await self.referencesUseCase.createTrackingBranch(
				named: remoteBranch.name,
				tracking: remoteBranch.fullName,
				at: repositoryURL
			)
		}
	}

	func didRequestDeleteBranch() {
		guard let branch = selectedBranch else { return }
		didPresentBranchDeletion(branch)
	}

	func didPresentBranchDeletion(_ branch: GitBranch) {
		guard !branch.isCurrent, operationState.isIdle, !isLoading else { return }
		didRequestConfirmation(.deleteBranch(branch))
	}

	func didRequestRenameBranch(_ branch: GitBranch, to newName: String) {
		guard let repositoryURL = repositoryURL() else { return }
		let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !newName.isEmpty, newName != branch.name else { return }
		requestMutation {
			let snapshot = try await self.referencesUseCase.renameBranch(
				named: branch.name,
				to: newName,
				at: repositoryURL
			)
			self.selectedBranchID = newName
			return snapshot
		}
	}

	func didPresentBranchRename(_ branch: GitBranch) {
		guard operationState.isIdle, !isLoading else { return }
		branchRenameName = branch.name
		pendingBranchRename = branch
	}

	func didDismissBranchRename() {
		pendingBranchRename = nil
		branchRenameName = ""
	}

	func didConfirmBranchRename() {
		guard let branch = pendingBranchRename else { return }
		let name = branchRenameName
		didDismissBranchRename()
		didRequestRenameBranch(branch, to: name)
	}

	func didRequestMergeBranch(_ branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), canMergeBranch(branch) else { return }
		requestMutation {
			try await self.referencesUseCase.mergeBranch(named: branch.name, at: repositoryURL)
		}
	}

	func didRequestRebase(onto branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), canRebaseOnto(branch), let operationsUseCase else {
			return
		}
		requestMutation {
			try await operationsUseCase.rebase(onto: branch.name, at: repositoryURL)
		}
	}

	func didRequestCherryPick(_ commit: GitCommit, mainline: Int? = nil) {
		didPerformCommitAction(.cherryPick(commit), mainline: mainline)
	}

	func didRequestRevert(_ commit: GitCommit, mainline: Int? = nil) {
		didPerformCommitAction(.revert(commit), mainline: mainline)
	}

	func didPresentCommitAction(_ action: PendingMainlineAction) {
		guard !operationState.isDetached else { return }
		if action.commit.parentHashes.count > 1 {
			pendingMainlineAction = action
		} else {
			didPerformCommitAction(action, mainline: nil)
		}
	}

	func didPerformPendingMainlineAction(parent: Int) {
		guard let action = pendingMainlineAction else { return }
		pendingMainlineAction = nil
		didPerformCommitAction(action, mainline: parent)
	}

	func didPresentReset(_ commit: GitCommit) {
		guard operationState.isIdle, !operationState.isDetached, !isLoading else { return }
		resetMode = .mixed
		pendingResetCommit = commit
	}

	func didConfirmReset() {
		guard let commit = pendingResetCommit else { return }
		let mode = resetMode
		pendingResetCommit = nil
		if mode == .hard {
			didPresentHardReset(commit)
		} else {
			didRequestReset(commit, mode: mode)
		}
	}

	func didRequestReset(_ commit: GitCommit, mode: GitResetMode) {
		guard
			let repositoryURL = repositoryURL(),
			operationState.isIdle,
			!operationState.isDetached,
			let operationsUseCase
		else { return }
		requestMutation {
			try await operationsUseCase.reset(to: commit.hash, mode: mode, at: repositoryURL)
		}
	}

	func didPerformOperationAction(_ action: RepositoryOperationAction) {
		guard
			let repositoryURL = repositoryURL(),
			let operation = operationState.operation,
			let operationsUseCase,
			action != .continue || conflicts.isEmpty
		else { return }
		requestMutation {
			try await operationsUseCase.perform(action, for: operation.kind, at: repositoryURL)
		}
	}

	func didPresentOperationAction(_ action: RepositoryOperationAction) {
		guard let operation = operationState.operation, action != .continue else { return }
		didRequestConfirmation(.operation(action, operation.kind))
	}

	func didViewConflicts() {
		guard let conflict = conflicts.first else { return }
		didRequestViewConflicts(conflict)
	}

	func didRequestPull() {
		guard let repositoryURL = repositoryURL(), operationState.isIdle, !isLoading else { return }
		networkTask?.cancel()
		networkTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let preparation = try await referencesUseCase.preparePull(at: repositoryURL)
				didProduceSnapshot(preparation.snapshot)
				if case .diverged(let divergence) = preparation.outcome {
					pendingPullDivergence = divergence
				}
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: repositoryURL)
			}
		}
	}

	func didResolvePull(using resolution: RepositoryPullResolution) {
		guard let repositoryURL = repositoryURL(), let divergence = pendingPullDivergence else {
			return
		}
		pendingPullDivergence = nil
		requestNetworkMutation {
			try await self.referencesUseCase.resolvePull(
				divergence,
				using: resolution,
				at: repositoryURL
			)
		}
	}

	func didDismissPullDivergence() {
		pendingPullDivergence = nil
	}

	func didRequestCancelOperation() {
		cancelTasks()
	}

	func didRequestFetchAll() {
		guard let repositoryURL = repositoryURL() else { return }
		requestNetworkMutation {
			try await self.referencesUseCase.fetchAll(at: repositoryURL)
		}
	}

	func didRequestFetch(remoteName: String) {
		guard
			let repositoryURL = repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		requestNetworkMutation {
			try await self.referencesUseCase.fetch(remote: remoteName, at: repositoryURL)
		}
	}

	func didRequestPush(remoteName: String? = nil) {
		guard let repositoryURL = repositoryURL(), pushAction != .unavailable else { return }
		requestNetworkMutation {
			try await self.referencesUseCase.push(
				currentBranch: self.currentBranch,
				remotes: self.remotes,
				operationState: self.operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	func didPresentForcePushConfirmation(remoteName: String? = nil) {
		guard pushAction != .unavailable else { return }
		didRequestConfirmation(.forcePush(remoteName: remoteName))
	}

	func didRequestPushTags(remoteName: String) {
		guard
			let repositoryURL = repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		requestNetworkMutation {
			try await self.referencesUseCase.pushTags(remote: remoteName, at: repositoryURL)
		}
	}

	func didRequestAddRemote(name: String, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.referencesUseCase.addRemote(
				named: name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		}
	}

	func didPresentAddRemote() {
		remoteEditorPresentation = .add
	}

	func didPresentRemoteEditor(_ remote: GitRemote) {
		remoteEditorPresentation = .edit(remote)
	}

	func didPresentRemoteRename(_ remote: GitRemote) {
		pendingRemoteRename = remote
	}

	func didRequestRenameRemote(_ remote: GitRemote, to newName: String) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			let snapshot = try await self.referencesUseCase.renameRemote(
				named: remote.name,
				to: newName,
				at: repositoryURL
			)
			self.selectedRemoteID = newName
			return snapshot
		}
	}

	func didRequestUpdateRemote(_ remote: GitRemote, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.referencesUseCase.updateRemote(
				named: remote.name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		}
	}

	func didPresentRemoteDeletion(_ remote: GitRemote) {
		guard !isLoading else { return }
		didRequestConfirmation(.deleteRemote(remote))
	}

	func didRequestDeleteRemote(_ remote: GitRemote) {
		requestDeleteRemote(remote)
	}

	func didPresentRemoteBranchDeletion(_ branch: GitRemoteBranch) {
		guard operationState.isIdle, !isLoading else { return }
		didRequestConfirmation(.deleteRemoteBranch(branch))
	}

	func didRequestDeleteRemoteBranch(_ branch: GitRemoteBranch) {
		requestDeleteRemoteBranch(branch)
	}

	func didConfirm(_ confirmation: PendingRepositoryConfirmation) {
		switch confirmation {
		case .deleteBranch(let branch):
			requestDeleteBranch(branch)
		case .deleteTag(let tag):
			requestDeleteTag(tag)
		case .forcePush(let remoteName):
			requestForcePush(remoteName: remoteName)
		case .operation(let action, let operation):
			requestOperationAction(action, operation: operation)
		case .hardReset(let commit):
			didRequestReset(commit, mode: .hard)
		case .checkoutCommit(let commit):
			requestCheckoutCommit(commit)
		case .deleteRemote(let remote):
			requestDeleteRemote(remote)
		case .deleteRemoteBranch(let branch):
			requestDeleteRemoteBranch(branch)
		case .discard, .discardHunk, .markConflictResolved, .dropStash:
			break
		}
	}

	private func requestCheckoutCommit(_ commit: GitCommit) {
		guard let repositoryURL = repositoryURL(), operationState.isIdle, changes.isEmpty else {
			return
		}
		requestMutation {
			try await self.referencesUseCase.checkoutCommit(commit.hash, at: repositoryURL)
		}
	}

	private func requestDeleteBranch(_ branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), !branch.isCurrent, operationState.isIdle else {
			return
		}
		requestMutation {
			try await self.referencesUseCase.deleteBranch(named: branch.name, at: repositoryURL)
		}
	}

	private func requestDeleteTag(_ tag: GitTag) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.referencesUseCase.deleteTag(named: tag.name, at: repositoryURL)
		}
	}

	private func requestForcePush(remoteName: String?) {
		guard let repositoryURL = repositoryURL(), pushAction != .unavailable else { return }
		requestNetworkMutation {
			try await self.referencesUseCase.forcePush(
				currentBranch: self.currentBranch,
				remotes: self.remotes,
				operationState: self.operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	private func requestOperationAction(
		_ action: RepositoryOperationAction,
		operation: RepositoryOperationKind
	) {
		guard
			let repositoryURL = repositoryURL(),
			let operationsUseCase,
			operationState.operation?.kind == operation
		else { return }
		requestMutation {
			try await operationsUseCase.perform(action, for: operation, at: repositoryURL)
		}
	}

	func didPresentHardReset(_ commit: GitCommit) {
		guard operationState.isIdle, !operationState.isDetached, !isLoading else { return }
		didRequestConfirmation(.hardReset(commit))
	}

	private func requestDeleteRemote(_ remote: GitRemote) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.referencesUseCase.deleteRemote(named: remote.name, at: repositoryURL)
		}
	}

	private func requestDeleteRemoteBranch(_ branch: GitRemoteBranch) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.referencesUseCase.deleteRemoteBranch(branch, at: repositoryURL)
		}
	}

	private func didPerformCommitAction(_ action: PendingMainlineAction, mainline: Int?) {
		guard
			let repositoryURL = repositoryURL(),
			operationState.isIdle,
			!operationState.isDetached,
			let operationsUseCase
		else { return }
		requestMutation {
			switch action {
			case .cherryPick(let commit):
				return try await operationsUseCase.cherryPick(
					commitHash: commit.hash,
					mainline: mainline,
					at: repositoryURL
				)
			case .revert(let commit):
				return try await operationsUseCase.revert(
					commitHash: commit.hash,
					mainline: mainline,
					at: repositoryURL
				)
			}
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: expectedRepositoryURL)
			}
		}
	}

	private func requestNetworkMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL() else { return }
		networkTask?.cancel()
		networkTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: expectedRepositoryURL)
			}
		}
	}

	private func restoreSnapshot(at repositoryURL: URL) async {
		if let snapshot = try? await contentUseCase.loadSnapshot(at: repositoryURL) {
			didProduceSnapshot(snapshot)
		}
	}

	private func preserveSelection() {
		if branches.contains(where: { $0.id == selectedBranchID }) == false {
			selectedBranchID = branches.first(where: \.isCurrent)?.id ?? branches.first?.id
		}
		if remotes.contains(where: { $0.id == selectedRemoteID }) == false {
			selectedRemoteID = remotes.first?.id
		}
	}

	private var operationStateTitle: String {
		if operationState.hasConflicts, operationState.operation == nil {
			return "Conflicts"
		}
		switch operationState.operation?.kind {
		case .merge:
			return "Merge in Progress"
		case .rebase:
			return "Rebase in Progress"
		case .cherryPick:
			return "Cherry-pick in Progress"
		case .revert:
			return "Revert in Progress"
		case .none:
			return operationState.isDetached ? "Detached HEAD" : "No Branch"
		}
	}
}
