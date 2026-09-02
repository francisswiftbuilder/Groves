import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RemotesViewModel: ObservableObject {
	public struct Actions {
		let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		let didReceiveError: @MainActor (String) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
		}
	}

	public struct Dependencies {
		let contentUseCase: any RepositoryContentUseCase
		let referencesUseCase: any RepositoryReferencesUseCase
		let repositoryURL: @MainActor () -> URL?

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

	@Published public var selectedRemoteID: String?
	@Published public private(set) var remotes: [GitRemote] = []
	@Published public private(set) var isLoading = false
	@Published var editorPresentation: RemoteEditorPresentation?
	@Published var pendingRename: GitRemote?
	@Published var pendingConfirmation: RepositoryRemoteConfirmation?

	private let dependencies: Dependencies
	private let actions: Actions
	private var mutationTask: Task<Void, Never>?

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
		mutationTask?.cancel()
		mutationTask = nil
		selectedRemoteID = nil
		remotes = []
		isLoading = false
		editorPresentation = nil
		pendingRename = nil
		pendingConfirmation = nil
	}

	public func didPresentAddRemote() {
		editorPresentation = .add
	}

	public func didPresentEditor(_ remote: GitRemote) {
		editorPresentation = .edit(remote)
	}

	public func didPresentRename(_ remote: GitRemote) {
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
		editorPresentation = nil
	}

	func didDismissRename() {
		pendingRename = nil
	}

	func didDismissConfirmation() {
		pendingConfirmation = nil
	}

	func didRequestAddRemote(name: String, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.addRemote(
				named: name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		}
	}

	func didRequestRename(_ remote: GitRemote, to newName: String) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			let snapshot = try await self.dependencies.referencesUseCase.renameRemote(
				named: remote.name,
				to: newName,
				at: repositoryURL
			)
			self.selectedRemoteID = newName
			return snapshot
		}
	}

	func didRequestUpdate(_ remote: GitRemote, fetchURL: String, pushURL: String?) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.updateRemote(
				named: remote.name,
				fetchURL: fetchURL,
				pushURL: pushURL,
				at: repositoryURL
			)
		}
	}

	func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
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
		requestMutation {
			try await self.dependencies.referencesUseCase.deleteRemote(
				named: remote.name,
				at: repositoryURL
			)
		}
	}

	private func requestDelete(_ branch: GitRemoteBranch) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			try await self.dependencies.referencesUseCase.deleteRemoteBranch(
				branch,
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
}
