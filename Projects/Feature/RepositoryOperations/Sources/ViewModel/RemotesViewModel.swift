import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class RemotesViewModel {
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

	public var selectedRemoteID: String?
	public private(set) var remotes: [GitRemote] = []
	public private(set) var isLoading = false
	private(set) var mutationErrorMessage: String?
	var editorPresentation: RemoteEditorPresentation?
	var pendingRename: GitRemote?
	var pendingConfirmation: RepositoryRemoteConfirmation?

	private let dependencies: Dependencies
	private let actions: Actions
	@ObservationIgnored private var mutationTask: Task<Void, Never>?
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0
	private var editorPresentationID = UUID()
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

	public var selectedRemote: GitRemote? {
		remotes.first { $0.id == selectedRemoteID }
	}

	public var remoteBranches: [GitRemoteBranch] {
		remotes.flatMap(\.branches)
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		if remotes != snapshot.remotes {
			remotes = snapshot.remotes
		}
		if remotes.contains(where: { $0.id == selectedRemoteID }) == false {
			let selection = remotes.first?.id
			if selectedRemoteID != selection {
				selectedRemoteID = selection
			}
		}
	}

	public func reset() {
		onDisappear()
		selectedRemoteID = nil
		remotes = []
		isLoading = false
		editorPresentation = nil
		pendingRename = nil
		pendingConfirmation = nil
		mutationErrorMessage = nil
	}

	public func onDisappear() {
		mutationTask?.cancel()
		mutationTask = nil
		activeMutationRequestID = nil
		isLoading = false
	}

	public func didPresentAddRemote() {
		editorPresentationID = UUID()
		mutationErrorMessage = nil
		editorPresentation = .add
	}

	public func didPresentEditor(_ remote: GitRemote) {
		editorPresentationID = UUID()
		mutationErrorMessage = nil
		editorPresentation = .edit(remote)
	}

	public func didPresentRename(_ remote: GitRemote) {
		renamePresentationID = UUID()
		mutationErrorMessage = nil
		pendingRename = remote
	}

	public func didPresentDeletion(_ remote: GitRemote) {
		guard !isLoading else { return }
		pendingConfirmation = .deleteRemote(remote)
	}

	public func didPresentBranchDeletion(_ branch: GitRemoteBranch) {
		guard !isLoading else { return }
		pendingConfirmation = .deleteRemoteBranch(branch)
	}

	func didDismissEditor() {
		editorPresentationID = UUID()
		editorPresentation = nil
	}

	func didDismissRename() {
		renamePresentationID = UUID()
		pendingRename = nil
	}

	func didDismissConfirmation() {
		pendingConfirmation = nil
	}

	func didRequestAddRemote(name: String, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let presentationID = editorPresentationID
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.addRemote(
				named: name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		} didSucceed: { [weak self] in
			guard let self, self.editorPresentationID == presentationID else { return }
			self.didDismissEditor()
		}
	}

	func didRequestRename(_ remote: GitRemote, to newName: String) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let presentationID = renamePresentationID
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			let snapshot = try await referencesUseCase.renameRemote(
				named: remote.name,
				to: newName,
				at: repositoryURL
			)
			return snapshot
		} didSucceed: { [weak self] in
			guard let self else { return }
			self.selectedRemoteID = newName
			if self.renamePresentationID == presentationID {
				self.didDismissRename()
			}
		}
	}

	func didRequestUpdate(_ remote: GitRemote, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let presentationID = editorPresentationID
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.updateRemote(
				named: remote.name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		} didSucceed: { [weak self] in
			guard let self, self.editorPresentationID == presentationID else { return }
			self.didDismissEditor()
		}
	}

	func didConfirmPendingConfirmation() {
		guard !isLoading, let confirmation = pendingConfirmation else { return }
		pendingConfirmation = nil
		switch confirmation {
		case .deleteRemote(let remote):
			requestDelete(remote)
		case .deleteRemoteBranch(let branch):
			requestDelete(branch)
		}
	}

	private func requestDelete(_ remote: GitRemote) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteRemote(
				named: remote.name,
				at: repositoryURL
			)
		}
	}

	private func requestDelete(_ branch: GitRemoteBranch) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestMutation {
			try await referencesUseCase.deleteRemoteBranch(
				branch,
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

}
