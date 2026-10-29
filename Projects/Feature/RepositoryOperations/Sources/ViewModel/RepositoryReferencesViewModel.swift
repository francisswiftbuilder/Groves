import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositoryReferencesViewModel: ObservableObject {
	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
		}
	}

	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase
		public let referencesUseCase: any RepositoryReferencesUseCase
		public let repositoryURL: @MainActor () -> URL?

		public init(
			contentUseCase: any RepositoryContentUseCase,
			referencesUseCase: any RepositoryReferencesUseCase,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.contentUseCase = contentUseCase
			self.referencesUseCase = referencesUseCase
			self.repositoryURL = repositoryURL
		}
	}

	@Published public var selectedBranchID: String?
	@Published public private(set) var branches: [GitBranch] = []
	@Published public private(set) var tags: [GitTag] = []
	@Published public private(set) var operationState: RepositoryOperationState = .normal
	@Published public private(set) var isLoading = false
	@Published private(set) var mutationErrorMessage: String?
	@Published var newBranchName = ""
	@Published var isPresentingNewBranch = false
	@Published private(set) var pendingBranchStartCommit: GitCommit?
	@Published var branchRenameName = ""
	@Published var pendingBranchRename: GitBranch?
	@Published var newTagName = ""
	@Published var newTagMessage = ""
	@Published private(set) var pendingTagCommit: GitCommit?
	@Published var pendingConfirmation: RepositoryReferenceConfirmation?

	private let dependencies: Dependencies
	private let actions: Actions
	private var changes: [WorkingTreeChange] = []
	private var mutationTask: Task<Void, Never>?
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0
	private var branchPresentationID = UUID()
	private var tagPresentationID = UUID()
	private var renamePresentationID = UUID()

	public init(
		dependencies: Dependencies,
		actions: Actions
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
		onDisappear()
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
		mutationErrorMessage = nil
	}

	public func onDisappear() {
		mutationTask?.cancel()
		mutationTask = nil
		activeMutationRequestID = nil
		isLoading = false
	}

	public func didPresentNewBranch(from commit: GitCommit? = nil) {
		branchPresentationID = UUID()
		mutationErrorMessage = nil
		newBranchName = ""
		pendingBranchStartCommit = commit
		isPresentingNewBranch = true
	}

	public func didDismissNewBranch() {
		branchPresentationID = UUID()
		newBranchName = ""
		pendingBranchStartCommit = nil
		isPresentingNewBranch = false
	}

	public func didRequestCreateBranch() {
		guard let repositoryURL = dependencies.repositoryURL(), operationState.isIdle else { return }
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		let startCommit = pendingBranchStartCommit
		let presentationID = branchPresentationID
		let submittedName = newBranchName
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			let snapshot: RepositorySnapshot
			if let startCommit {
				snapshot = try await referencesUseCase.createBranch(
					named: name,
					from: startCommit.hash,
					at: repositoryURL
				)
			} else {
				snapshot = try await referencesUseCase.createBranch(
					named: name,
					at: repositoryURL
				)
			}
			return snapshot
		} didSucceed: { [weak self] in
			guard let self, self.branchPresentationID == presentationID,
				self.newBranchName == submittedName
			else { return }
			self.didDismissNewBranch()
		}
	}

	public func didPresentNewTag(for commit: GitCommit) {
		tagPresentationID = UUID()
		mutationErrorMessage = nil
		newTagName = ""
		newTagMessage = ""
		pendingTagCommit = commit
	}

	public func didDismissNewTag() {
		tagPresentationID = UUID()
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
		let presentationID = tagPresentationID
		let submittedName = newTagName
		let submittedMessage = newTagMessage
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			let snapshot = try await referencesUseCase.createTag(
				named: name,
				message: message,
				commitHash: commit.hash,
				at: repositoryURL
			)
			return snapshot
		} didSucceed: { [weak self] in
			guard let self, self.tagPresentationID == presentationID,
				self.newTagName == submittedName, self.newTagMessage == submittedMessage
			else { return }
			self.didDismissNewTag()
		}
	}

	public func didPresentTagDeletion(_ tag: GitTag) {
		guard !isLoading else { return }
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
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.switchBranch(
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
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.createTrackingBranch(
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
		renamePresentationID = UUID()
		mutationErrorMessage = nil
		branchRenameName = branch.name
		pendingBranchRename = branch
	}

	func didDismissBranchRename() {
		renamePresentationID = UUID()
		pendingBranchRename = nil
		branchRenameName = ""
	}

	func didConfirmBranchRename() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let branch = pendingBranchRename
		else { return }
		let name = branchRenameName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty, name != branch.name, !isLoading else { return }
		let presentationID = renamePresentationID
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			let snapshot = try await referencesUseCase.renameBranch(
				named: branch.name,
				to: name,
				at: repositoryURL
			)
			return snapshot
		} didSucceed: { [weak self] in
			guard let self else { return }
			self.selectedBranchID = name
			if self.renamePresentationID == presentationID {
				self.didDismissBranchRename()
			}
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	func didConfirmPendingConfirmation() {
		guard !isLoading, let confirmation = pendingConfirmation else { return }
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
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.checkoutCommit(
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
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteBranch(
				named: branch.name,
				at: repositoryURL
			)
		}
	}

	private func requestDeleteTag(_ tag: GitTag) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteTag(
				named: tag.name,
				at: repositoryURL
			)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot,
		didSucceed: @escaping @MainActor () -> Void = {}
	) {
		guard !isLoading, let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		mutationRequestSequence += 1
		let requestID = mutationRequestSequence
		activeMutationRequestID = requestID
		isLoading = true
		mutationErrorMessage = nil
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				try Task.checkCancellation()
				let snapshot = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeMutationRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else { return }
				didSucceed()
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeMutationRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else { return }
				mutationErrorMessage = error.localizedDescription
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: expectedRepositoryURL
				) {
					guard !Task.isCancelled, activeMutationRequestID == requestID,
						dependencies.repositoryURL() == expectedRepositoryURL
					else { return }
					actions.didProduceSnapshot(snapshot)
				}
			}
		}
	}

	private func finishMutation(id: Int) {
		guard activeMutationRequestID == id else { return }
		activeMutationRequestID = nil
		mutationTask = nil
		isLoading = false
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
