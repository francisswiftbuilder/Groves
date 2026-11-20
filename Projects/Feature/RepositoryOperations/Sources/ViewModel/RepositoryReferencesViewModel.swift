import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class RepositoryReferencesViewModel {
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

	public var selectedBranchID: String?
	public private(set) var branches: [GitBranch] = []
	public private(set) var tags: [GitTag] = []
	public private(set) var operationState: RepositoryOperationState = .normal
	public private(set) var isLoading = false
	private(set) var mutationErrorMessage: String?
	var newBranchName = ""
	var isPresentingNewBranch = false
	private(set) var pendingBranchStartCommit: GitCommit?
	var branchRenameName = ""
	var pendingBranchRename: GitBranch?
	var checkOutNewBranch = true
	private(set) var mutationErrorDetails: String?
	private(set) var pendingBranchRemote: GitRemoteBranch?
	var newTagName = ""
	var newTagMessage = ""
	private(set) var pendingTagCommit: GitCommit?
	var pendingConfirmation: RepositoryReferenceConfirmation?
	private(set) var deletionRemoteBranch: GitRemoteBranch?
	private var remotes: [GitRemote] = []

	private let dependencies: Dependencies
	private let actions: Actions
	private var changes: [WorkingTreeChange] = []
	@ObservationIgnored private var mutationTask: Task<Void, Never>?
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

	public var canCreateBranch: Bool {
		operationState.isIdle && !isLoading && (currentBranch != nil || operationState.isDetached)
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
		remotes = snapshot.remotes
		preserveSelection()
	}

	public func reset() {
		onDisappear()
		selectedBranchID = nil
		branches = []
		remotes = []
		tags = []
		changes = []
		operationState = .normal
		isLoading = false
		didDismissNewBranch()
		didDismissNewTag()
		didDismissBranchRename()
		didDismissPendingConfirmation()
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
		checkOutNewBranch = true
		pendingBranchRemote = nil
		pendingBranchStartCommit = commit
		isPresentingNewBranch = true
	}

	public func didDismissNewBranch() {
		branchPresentationID = UUID()
		newBranchName = ""
		pendingBranchRemote = nil
		pendingBranchStartCommit = nil
		isPresentingNewBranch = false
	}

	public func didRequestCreateBranch() {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		guard operationState.isIdle else {
			mutationErrorMessage = "Finish the current Git operation before creating a branch."
			return
		}
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		let startCommit = pendingBranchStartCommit
		let source: GitBranchCreationSource
		if let pendingBranchRemote {
			source = .remoteBranch(pendingBranchRemote)
		} else if let startCommit {
			source = .commit(startCommit.hash)
		} else {
			source = .head
		}
		let checkout = checkOutNewBranch
		let presentationID = branchPresentationID
		let submittedName = newBranchName
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation(
			{
				try await referencesUseCase.createBranch(
					named: name, from: source, checkout: checkout, at: repositoryURL)
			}, formError: true,
			applyResult: { [weak self] result in
				guard let self else { return }
				if branchPresentationID == presentationID, newBranchName == submittedName {
					didDismissNewBranch()
				}
				applyReferenceResult(result)
			})
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
		requestMutation(
			{
				try await referencesUseCase.createTag(
					named: name,
					message: message,
					commitHash: commit.hash,
					at: repositoryURL
				)
			}, formError: true,
			applyResult: { [weak self] result in
				guard let self else { return }
				if tagPresentationID == presentationID, newTagName == submittedName,
					newTagMessage == submittedMessage
				{
					didDismissNewTag()
				}
				applyReferenceResult(result)
			})
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
		guard remoteBranch.remoteReference != nil else {
			actions.didReceiveError(
				"This tracking reference has no verified server branch. Review the remote’s fetch mappings."
			)
			return
		}
		didPresentNewBranch()
		pendingBranchRemote = remoteBranch
		newBranchName = remoteBranch.name
		if branches.contains(where: { $0.name == remoteBranch.name }) {
			mutationErrorMessage = "A local branch already uses this name. Choose another name."
		}
	}

	public func didPresentBranchDeletion(_ branch: GitBranch) {
		guard !branch.isCurrent, operationState.isIdle, !isLoading else { return }
		deletionRemoteBranch = remotes.flatMap(\.branches).first {
			branch.tracks($0) && !$0.pushURLs.isEmpty
		}
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
		deletionRemoteBranch = nil
	}

	func didConfirmPendingConfirmation(
		deleteLinkedBranch: Bool = false, didDeleteTag: @escaping @MainActor (GitTag) -> Void = { _ in }
	) {
		guard !isLoading, let confirmation = pendingConfirmation else { return }
		let remoteBranch = deleteLinkedBranch ? deletionRemoteBranch : nil
		didDismissPendingConfirmation()
		switch confirmation {
		case .deleteBranch(let branch):
			requestDeleteBranch(branch, remoteBranch: remoteBranch)
		case .deleteTag(let tag):
			requestDeleteTag(tag, didDelete: didDeleteTag)
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

	private func requestDeleteBranch(_ branch: GitBranch, remoteBranch: GitRemoteBranch?) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!branch.isCurrent,
			operationState.isIdle
		else { return }
		guard let current = branches.first(where: { $0.name == branch.name }),
			!current.isCurrent, current.hash == branch.hash
		else {
			actions.didReceiveError("The local branch changed. Review the deletion again.")
			return
		}
		if let remoteBranch,
			!current.tracks(remoteBranch)
				|| !remotes.flatMap(\.branches).contains(remoteBranch)
		{
			actions.didReceiveError("The remote branch changed. Review the deletion again.")
			return
		}
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteBranches(
				localBranches: [current], remoteBranch: remoteBranch, at: repositoryURL)
		} applyResult: { [weak self] result in
			self?.applyReferenceResult(result)
		}
	}

	private func requestDeleteTag(_ tag: GitTag, didDelete: @escaping @MainActor (GitTag) -> Void) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteTag(
				tag,
				at: repositoryURL
			)
		} applyResult: { [weak self] result in
			didDelete(tag)
			self?.applyReferenceResult(result)
		}
	}

	private func applyReferenceResult(_ result: RepositoryReferenceMutationResult) {
		if let snapshot = result.snapshot { actions.didProduceSnapshot(snapshot) }
		if let message = result.message {
			mutationErrorMessage = message
			actions.didReceiveError(message)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot,
		didSucceed: @escaping @MainActor () -> Void = {}
	) {
		requestMutation(operation) { [weak self] snapshot in
			didSucceed()
			self?.actions.didProduceSnapshot(snapshot)
		}
	}

	private func requestMutation<Result>(
		_ operation: @escaping @MainActor () async throws -> Result,
		formError: Bool = false,
		applyResult: @escaping @MainActor (Result) -> Void
	) {
		guard !isLoading, let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		mutationRequestSequence += 1
		let requestID = mutationRequestSequence
		activeMutationRequestID = requestID
		isLoading = true
		mutationErrorMessage = nil
		mutationErrorDetails = nil
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				try Task.checkCancellation()
				let result = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeMutationRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else { return }
				applyResult(result)
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeMutationRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else { return }
				mutationErrorMessage = error.localizedDescription
				if case GitRepositoryError.referenceOperationFailed(_, let details) = error {
					mutationErrorDetails = details
				}
				if !formError { actions.didReceiveError(error.localizedDescription) }
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
