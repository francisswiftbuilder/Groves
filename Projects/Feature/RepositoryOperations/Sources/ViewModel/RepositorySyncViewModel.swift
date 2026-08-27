import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositorySyncViewModel: ObservableObject {
	@Published var pendingPullDivergence: RepositoryPullDivergence?
	@Published var pendingConfirmation: RepositorySyncConfirmation?
	@Published public private(set) var isLoading = false
	@Published public private(set) var remotes: [GitRemote] = []

	private let dependencies: RepositorySyncViewModelDependencies
	private let actions: RepositorySyncViewModelActions
	private var currentBranch: GitBranch?
	private var operationState: RepositoryOperationState = .normal
	private var networkTask: Task<Void, Never>?

	public init(
		dependencies: RepositorySyncViewModelDependencies,
		actions: RepositorySyncViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		networkTask?.cancel()
	}

	var pushAction: RepositoryPushAction {
		dependencies.referencesUseCase.pushAction(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState
		)
	}

	public var forcePushConfirmationTitle: String {
		"Force Push \(currentBranch?.name ?? "No Branch")?"
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		currentBranch = snapshot.branches.first(where: \.isCurrent)
		remotes = snapshot.remotes
		operationState = snapshot.operationState
	}

	public func reset() {
		networkTask?.cancel()
		networkTask = nil
		pendingPullDivergence = nil
		pendingConfirmation = nil
		isLoading = false
		currentBranch = nil
		remotes = []
		operationState = .normal
	}

	public func didRequestPull() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			operationState.isIdle,
			!isLoading
		else { return }
		networkTask?.cancel()
		networkTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let preparation = try await dependencies.referencesUseCase.preparePull(
					at: repositoryURL
				)
				actions.didProduceSnapshot(preparation.snapshot)
				if case .diverged(let divergence) = preparation.outcome {
					pendingPullDivergence = divergence
				}
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: repositoryURL)
			}
		}
	}

	public func didResolvePull(using resolution: RepositoryPullResolution) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let divergence = pendingPullDivergence
		else { return }
		pendingPullDivergence = nil
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.resolvePull(
				divergence,
				using: resolution,
				at: repositoryURL
			)
		}
	}

	public func didDismissPullDivergence() {
		pendingPullDivergence = nil
	}

	public func didRequestCancelOperation() {
		networkTask?.cancel()
	}

	public func didRequestFetchAll() {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.fetchAll(at: repositoryURL)
		}
	}

	public func didRequestFetch(remoteName: String) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.fetch(
				remote: remoteName,
				at: repositoryURL
			)
		}
	}

	func didRequestPush(remoteName: String? = nil) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			pushAction != .unavailable
		else { return }
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.push(
				currentBranch: self.currentBranch,
				remotes: self.remotes,
				operationState: self.operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	public func didPresentForcePushConfirmation(remoteName: String? = nil) {
		guard pushAction != .unavailable else { return }
		pendingConfirmation = .forcePush(remoteName: remoteName)
	}

	public func didRequestPushTags(remoteName: String) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.pushTags(
				remote: remoteName,
				at: repositoryURL
			)
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
		pendingConfirmation = nil
		switch confirmation {
		case .forcePush(let remoteName):
			requestForcePush(remoteName: remoteName)
		}
	}

	private func requestForcePush(remoteName: String?) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			pushAction != .unavailable
		else { return }
		requestNetworkMutation {
			try await self.dependencies.referencesUseCase.forcePush(
				currentBranch: self.currentBranch,
				remotes: self.remotes,
				operationState: self.operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	private func requestNetworkMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		networkTask?.cancel()
		networkTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				actions.didProduceSnapshot(try await operation())
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: expectedRepositoryURL)
			}
		}
	}

	private func restoreSnapshot(at repositoryURL: URL) async {
		if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(at: repositoryURL) {
			actions.didProduceSnapshot(snapshot)
		}
	}
}
