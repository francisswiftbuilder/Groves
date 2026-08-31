import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositoryReferencesViewModel: ObservableObject {
	@Published public var selectedBranchID: String?
	@Published public private(set) var branches: [GitBranch] = []
	@Published public private(set) var tags: [GitTag] = []
	@Published public private(set) var operationState: RepositoryOperationState = .normal
	@Published public private(set) var isLoading = false
	@Published var newBranchName = ""
	@Published var isPresentingNewBranch = false
	@Published private(set) var pendingBranchStartCommit: GitCommit?
	@Published var branchRenameName = ""
	@Published var pendingBranchRename: GitBranch?
	@Published var newTagName = ""
	@Published var newTagMessage = ""
	@Published private(set) var pendingTagCommit: GitCommit?
	@Published var pendingConfirmation: RepositoryReferenceConfirmation?

	private let dependencies: RepositoryReferencesViewModelDependencies
	private let actions: RepositoryReferencesViewModelActions
	private var changes: [WorkingTreeChange] = []
	private var mutationTask: Task<Void, Never>?

	public init(
		dependencies: RepositoryReferencesViewModelDependencies,
		actions: RepositoryReferencesViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		mutationTask?.cancel()
	}

	public var currentBranch: GitBranch? {
		branches.first(where: \.isCurrent)
	}

	public var currentBranchName: String {
		guard !operationState.isDetached else { return "Detached HEAD" }
		return currentBranch?.name ?? "No Branch"
	}

	public var currentBranchStatus: String {
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

	public var selectedBranch: GitBranch? {
		branches.first { $0.id == selectedBranchID }
	}

	public var canCheckoutCommit: Bool {
		operationState.isIdle && changes.isEmpty && !isLoading
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		if branches != snapshot.branches {
			branches = snapshot.branches
		}
		if tags != snapshot.tags {
			tags = snapshot.tags
		}
		if operationState != snapshot.operationState {
			operationState = snapshot.operationState
		}
		changes = snapshot.changes
		preserveSelection()
	}

	public func reset() {
		mutationTask?.cancel()
		mutationTask = nil
		selectedBranchID = nil
		branches = []
		tags = []
		changes = []
		operationState = .normal
		isLoading = false
		didDismissNewBranch()
		didDismissNewTag()
		didDismissBranchRename()
		pendingConfirmation = nil
	}

	public func didPresentNewBranch(from commit: GitCommit? = nil) {
		newBranchName = ""
		pendingBranchStartCommit = commit
		isPresentingNewBranch = true
	}

	public func didDismissNewBranch() {
		newBranchName = ""
		pendingBranchStartCommit = nil
		isPresentingNewBranch = false
	}

	public func didRequestCreateBranch() {
		guard let repositoryURL = dependencies.repositoryURL(), operationState.isIdle else { return }
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		let startCommit = pendingBranchStartCommit
		requestMutation {
			let snapshot: RepositorySnapshot
			if let startCommit {
				snapshot = try await self.dependencies.referencesUseCase.createBranch(
					named: name,
					from: startCommit.hash,
					at: repositoryURL
				)
			} else {
				snapshot = try await self.dependencies.referencesUseCase.createBranch(
					named: name,
					at: repositoryURL
				)
			}
			self.didDismissNewBranch()
			return snapshot
		}
	}

	public func didPresentNewTag(for commit: GitCommit) {
		newTagName = ""
		newTagMessage = ""
		pendingTagCommit = commit
	}

	public func didDismissNewTag() {
		newTagName = ""
		newTagMessage = ""
		pendingTagCommit = nil
	}

	public func didRequestCreateTag() {
		guard let repositoryURL = dependencies.repositoryURL(), let commit = pendingTagCommit else {
			return
		}
		let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
		let message = newTagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		requestMutation {
			let snapshot = try await self.dependencies.referencesUseCase.createTag(
				named: name,
				message: message,
				commitHash: commit.hash,
				at: repositoryURL
			)
			self.didDismissNewTag()
			return snapshot
		}
	}

	public func didPresentTagDeletion(_ tag: GitTag) {
		pendingConfirmation = .deleteTag(tag)
	}

	public func didRequestSwitchBranch() {
		guard let branch = selectedBranch else { return }
		didRequestSwitchBranch(branch)
	}

	public func didRequestSwitchBranch(_ branch: GitBranch) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!branch.isCurrent,
			operationState.isIdle
		else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.switchBranch(
				named: branch.name,
				at: repositoryURL
			)
		}
	}

	public func didPresentCheckoutCommit(_ commit: GitCommit) {
		guard canCheckoutCommit else { return }
		pendingConfirmation = .checkoutCommit(commit)
	}

	public func didRequestCreateLocalBranch(from remoteBranch: GitRemoteBranch) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!branches.contains(where: { $0.name == remoteBranch.name }),
			operationState.isIdle
		else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.createTrackingBranch(
				named: remoteBranch.name,
				tracking: remoteBranch.fullName,
				at: repositoryURL
			)
		}
	}

	public func didPresentBranchDeletion(_ branch: GitBranch) {
		guard !branch.isCurrent, operationState.isIdle, !isLoading else { return }
		pendingConfirmation = .deleteBranch(branch)
	}

	public func didPresentBranchRename(_ branch: GitBranch) {
		guard operationState.isIdle, !isLoading else { return }
		branchRenameName = branch.name
		pendingBranchRename = branch
	}

	func didDismissBranchRename() {
		pendingBranchRename = nil
		branchRenameName = ""
	}

	func didConfirmBranchRename() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let branch = pendingBranchRename
		else { return }
		let name = branchRenameName.trimmingCharacters(in: .whitespacesAndNewlines)
		didDismissBranchRename()
		guard !name.isEmpty, name != branch.name else { return }
		requestMutation {
			let snapshot = try await self.dependencies.referencesUseCase.renameBranch(
				named: branch.name,
				to: name,
				at: repositoryURL
			)
			self.selectedBranchID = name
			return snapshot
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
		pendingConfirmation = nil
		switch confirmation {
		case .deleteBranch(let branch):
			requestDeleteBranch(branch)
		case .deleteTag(let tag):
			requestDeleteTag(tag)
		case .checkoutCommit(let commit):
			requestCheckoutCommit(commit)
		}
	}

	private func requestCheckoutCommit(_ commit: GitCommit) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			operationState.isIdle,
			changes.isEmpty
		else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.checkoutCommit(
				commit.hash,
				at: repositoryURL
			)
		}
	}

	private func requestDeleteBranch(_ branch: GitBranch) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!branch.isCurrent,
			operationState.isIdle
		else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.deleteBranch(
				named: branch.name,
				at: repositoryURL
			)
		}
	}

	private func requestDeleteTag(_ tag: GitTag) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.deleteTag(
				named: tag.name,
				at: repositoryURL
			)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				actions.didProduceSnapshot(try await operation())
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: expectedRepositoryURL
				) {
					actions.didProduceSnapshot(snapshot)
				}
			}
		}
	}

	private func preserveSelection() {
		if branches.contains(where: { $0.id == selectedBranchID }) == false {
			let selection = branches.first(where: \.isCurrent)?.id ?? branches.first?.id
			if selectedBranchID != selection {
				selectedBranchID = selection
			}
		}
	}

	private var operationStateTitle: String {
		if operationState.hasConflicts, operationState.operation == nil {
			return "Conflicts"
		}
		switch operationState.operation?.kind {
		case .merge: return "Merge in Progress"
		case .rebase: return "Rebase in Progress"
		case .cherryPick: return "Cherry-pick in Progress"
		case .revert: return "Revert in Progress"
		case .none: return operationState.isDetached ? "Detached HEAD" : "No Branch"
		}
	}
}
