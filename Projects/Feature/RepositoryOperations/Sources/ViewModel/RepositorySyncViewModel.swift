import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositorySyncViewModel: ObservableObject {
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

	public enum Activity: Equatable {
		case fetchAll
		case fetchRemote(String)
		case pull(String?)
		case push(String?)
		case forcePush(String?)
		case pushTags(String)

		public var statusDescription: String {
			switch self {
			case .fetchAll:
				"Fetching all remotes"
			case .fetchRemote(let remoteName):
				"Fetching \(remoteName)"
			case .pull(let branchName):
				"Pulling \(branchName ?? "current branch")"
			case .push(let branchName):
				"Pushing \(branchName ?? "current branch")"
			case .forcePush(let branchName):
				"Force pushing \(branchName ?? "current branch")"
			case .pushTags(let remoteName):
				"Pushing tags to \(remoteName)"
			}
		}

		public var cancellationLabel: String {
			switch self {
			case .fetchAll, .fetchRemote:
				"Cancel Fetch"
			case .pull:
				"Cancel Pull"
			case .push, .forcePush:
				"Cancel Push"
			case .pushTags:
				"Cancel Tag Push"
			}
		}

		public var isFetch: Bool {
			switch self {
			case .fetchAll, .fetchRemote:
				true
			case .pull, .push, .forcePush, .pushTags:
				false
			}
		}

		public var isPull: Bool {
			if case .pull = self {
				return true
			}
			return false
		}

		public var isPush: Bool {
			switch self {
			case .push, .forcePush, .pushTags:
				true
			case .fetchAll, .fetchRemote, .pull:
				false
			}
		}
	}

	@Published var pendingPullDivergence: RepositoryPullDivergence?
	@Published var pendingConfirmation: RepositorySyncConfirmation?
	@Published public private(set) var activity: Activity?
	@Published public private(set) var presentedActivity: Activity?
	@Published private var state = RepositorySyncState.empty

	private let dependencies: Dependencies
	private let actions: Actions
	private var currentBranch: GitBranch?
	private var operationState: RepositoryOperationState = .normal
	private var networkTask: Task<Void, Never>?
	private var activityPresentationTask: Task<Void, Never>?
	private var activeNetworkRequestID: Int?
	private var networkRequestSequence = 0

	public init(
		dependencies: Dependencies,
		actions: Actions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		networkTask?.cancel()
		activityPresentationTask?.cancel()
	}

	public var remotes: [GitRemote] {
		state.remotes
	}

	public var isLoading: Bool {
		activity != nil
	}

	var pushAction: RepositoryPushAction {
		state.pushAction
	}

	public var forcePushConfirmationTitle: String {
		"Force Push \(currentBranch?.name ?? "No Branch")?"
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		currentBranch = snapshot.branches.first(where: \.isCurrent)
		operationState = snapshot.operationState
		let nextState = RepositorySyncState(
			remotes: snapshot.remotes,
			pushAction: dependencies.referencesUseCase.pushAction(
				currentBranch: currentBranch,
				remotes: snapshot.remotes,
				operationState: operationState
			)
		)
		if state != nextState {
			state = nextState
		}
	}

	public func reset() {
		networkTask?.cancel()
		networkTask = nil
		activityPresentationTask?.cancel()
		activityPresentationTask = nil
		activeNetworkRequestID = nil
		pendingPullDivergence = nil
		pendingConfirmation = nil
		activity = nil
		presentedActivity = nil
		currentBranch = nil
		operationState = .normal
		state = .empty
	}

	public func onDisappear() {
		networkTask?.cancel()
		networkTask = nil
		activityPresentationTask?.cancel()
		activityPresentationTask = nil
		activeNetworkRequestID = nil
		activity = nil
		presentedActivity = nil
	}

	public func didRequestPull() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			operationState.isIdle,
			!isLoading
		else { return }
		networkTask?.cancel()
		let requestID = beginNetworkRequest(activity: .pull(currentBranch?.name))
		let referencesUseCase = dependencies.referencesUseCase
		networkTask = Task { [weak self] in
			defer { self?.finishNetworkRequest(id: requestID) }
			do {
				let preparation = try await referencesUseCase.preparePull(
					at: repositoryURL
				)
				guard let self, self.activeNetworkRequestID == requestID else { return }
				actions.didProduceSnapshot(preparation.snapshot)
				if case .diverged(let divergence) = preparation.outcome {
					pendingPullDivergence = divergence
				}
			} catch is CancellationError {
				return
			} catch {
				guard let self, self.activeNetworkRequestID == requestID else { return }
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
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkMutation(activity: .pull(currentBranch?.name)) {
			try await referencesUseCase.resolvePull(
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
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkMutation(activity: .fetchAll) {
			try await referencesUseCase.fetchAll(at: repositoryURL)
		}
	}

	public func didRequestFetch(remoteName: String) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkMutation(activity: .fetchRemote(remoteName)) {
			try await referencesUseCase.fetch(
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
		let referencesUseCase = dependencies.referencesUseCase
		let currentBranch = currentBranch
		let remotes = remotes
		let operationState = operationState
		requestNetworkMutation(activity: .push(currentBranch?.name)) {
			try await referencesUseCase.push(
				currentBranch: currentBranch,
				remotes: remotes,
				operationState: operationState,
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
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkMutation(activity: .pushTags(remoteName)) {
			try await referencesUseCase.pushTags(
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
		let referencesUseCase = dependencies.referencesUseCase
		let currentBranch = currentBranch
		let remotes = remotes
		let operationState = operationState
		requestNetworkMutation(activity: .forcePush(currentBranch?.name)) {
			try await referencesUseCase.forcePush(
				currentBranch: currentBranch,
				remotes: remotes,
				operationState: operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	private func requestNetworkMutation(
		activity: Activity,
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		networkTask?.cancel()
		let requestID = beginNetworkRequest(activity: activity)
		networkTask = Task { [weak self] in
			defer { self?.finishNetworkRequest(id: requestID) }
			do {
				let snapshot = try await operation()
				guard let self, self.activeNetworkRequestID == requestID else { return }
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, self.activeNetworkRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: expectedRepositoryURL)
			}
		}
	}

	private func beginNetworkRequest(activity: Activity) -> Int {
		networkRequestSequence += 1
		activeNetworkRequestID = networkRequestSequence
		self.activity = activity
		presentActivityAfterDelay(activity, requestID: networkRequestSequence)
		return networkRequestSequence
	}

	private func finishNetworkRequest(id: Int) {
		guard activeNetworkRequestID == id else { return }
		activityPresentationTask?.cancel()
		activityPresentationTask = nil
		activeNetworkRequestID = nil
		activity = nil
		presentedActivity = nil
	}

	private func presentActivityAfterDelay(_ activity: Activity, requestID: Int) {
		activityPresentationTask?.cancel()
		presentedActivity = nil
		activityPresentationTask = Task { [weak self] in
			do {
				try await Task.sleep(for: .milliseconds(250))
			} catch {
				return
			}
			guard
				let self,
				!Task.isCancelled,
				activeNetworkRequestID == requestID,
				self.activity == activity
			else { return }
			presentedActivity = activity
		}
	}

	private func restoreSnapshot(at repositoryURL: URL) async {
		if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(at: repositoryURL) {
			actions.didProduceSnapshot(snapshot)
		}
	}
}
