import DomainGitInterface
import Foundation
import OSLog
import Observation

@MainActor
@Observable
public final class RepositorySyncViewModel {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "com.francisswiftbuilder.pluminon",
		category: "RepositorySync")

	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void
		public let didFetchAutomatically: @MainActor () -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void,
			didFetchAutomatically: @escaping @MainActor () -> Void = {}
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
			self.didFetchAutomatically = didFetchAutomatically
		}
	}

	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase
		public let referencesUseCase: any RepositoryReferencesUseCase
		public let repositoryURL: @MainActor () -> URL?
		public let canAutomaticallyFetch: @MainActor () -> Bool
		public let automaticFetchInterval: Duration

		public init(
			contentUseCase: any RepositoryContentUseCase,
			referencesUseCase: any RepositoryReferencesUseCase,
			repositoryURL: @escaping @MainActor () -> URL?,
			canAutomaticallyFetch: @escaping @MainActor () -> Bool = { true },
			automaticFetchInterval: Duration = .seconds(60)
		) {
			self.contentUseCase = contentUseCase
			self.referencesUseCase = referencesUseCase
			self.repositoryURL = repositoryURL
			self.canAutomaticallyFetch = canAutomaticallyFetch
			self.automaticFetchInterval = automaticFetchInterval
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

	var pendingPullDivergence: RepositoryPullDivergence?
	var pendingConfirmation: RepositorySyncConfirmation?
	public private(set) var activity: Activity?
	public private(set) var presentedActivity: Activity?
	private var state = RepositorySyncState.empty

	private let dependencies: Dependencies
	private let actions: Actions
	private var currentBranch: GitBranch?
	private var operationState: RepositoryOperationState = .normal
	@ObservationIgnored private var networkTask: Task<Void, Never>?
	@ObservationIgnored private var activityPresentationTask: Task<Void, Never>?
	@ObservationIgnored private var automaticFetchTask: Task<Void, Never>?
	private var isAutomaticFetch = false
	private var forcePushContext: (repositoryURL: URL, branch: GitBranch, remotes: [GitRemote])?
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
		automaticFetchTask?.cancel()
	}

	public var remotes: [GitRemote] {
		state.remotes
	}

	public var isLoading: Bool {
		activity != nil
	}

	public var isBlockingLocalRefresh: Bool {
		isLoading && !isAutomaticFetch
	}

	public var canFetch: Bool { !isLoading && !remotes.isEmpty }
	public var canPull: Bool {
		!isLoading && operationState.isIdle && !operationState.isDetached
			&& currentBranch?.upstream != nil
	}
	public var canPush: Bool { !isLoading && pushAction != .unavailable }
	public var pushRemoteChoices: [String] {
		if case .chooseRemote(let names, _) = pushAction { return names }
		return []
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
		isAutomaticFetch = false
		forcePushContext = nil
	}

	public func onDisappear() {
		updateAutomaticFetching(isActive: false)
		networkTask?.cancel()
		networkTask = nil
		activityPresentationTask?.cancel()
		activityPresentationTask = nil
		activeNetworkRequestID = nil
		activity = nil
		presentedActivity = nil
		isAutomaticFetch = false
	}

	public func updateAutomaticFetching(isActive: Bool) {
		guard isActive else {
			automaticFetchTask?.cancel()
			automaticFetchTask = nil
			if isAutomaticFetch { networkTask?.cancel() }
			return
		}
		guard automaticFetchTask == nil else { return }
		let interval = dependencies.automaticFetchInterval
		automaticFetchTask = Task { @MainActor [weak self] in
			var delay = min(interval, .seconds(1))
			do {
				while !Task.isCancelled {
					try await Task.sleep(for: delay)
					guard let self else { return }
					delay = interval
					guard !isLoading, dependencies.canAutomaticallyFetch(), pendingConfirmation == nil,
						pendingPullDivergence == nil
					else {
						delay = min(interval, .seconds(1))
						continue
					}
					guard canFetch else { continue }
					requestAutomaticFetch()
				}
			} catch {}
		}
	}

	private func requestAutomaticFetch() {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkMutation(activity: .fetchAll, isAutomatic: true) {
			try await referencesUseCase.fetchAutomatically(at: repositoryURL)
			return nil
		}
	}

	public func didRequestPull() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let currentBranch,
			canPull
		else { return }
		networkTask?.cancel()
		let requestID = beginNetworkRequest(activity: .pull(currentBranch.name))
		let referencesUseCase = dependencies.referencesUseCase
		networkTask = Task { [weak self] in
			defer { self?.finishNetworkRequest(id: requestID) }
			do {
				try Task.checkCancellation()
				let preparation = try await referencesUseCase.preparePull(
					expecting: currentBranch, at: repositoryURL
				)
				try Task.checkCancellation()
				guard let self, self.activeNetworkRequestID == requestID,
					self.dependencies.repositoryURL() == repositoryURL
				else { return }
				actions.didProduceSnapshot(preparation.snapshot)
				if case .diverged(let divergence) = preparation.outcome {
					pendingPullDivergence = divergence
				}
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeNetworkRequestID == requestID,
					self.dependencies.repositoryURL() == repositoryURL
				else {
					return
				}
				actions.didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: repositoryURL, requestID: requestID)
			}
		}
	}

	public func didResolvePull(using resolution: RepositoryPullResolution) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let divergence = pendingPullDivergence,
			!isLoading
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

	public func didRequestPush(remoteName: String? = nil) {
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
		guard !isLoading, pushAction != .unavailable, let currentBranch,
			let repositoryURL = dependencies.repositoryURL()
		else { return }
		forcePushContext = (repositoryURL, currentBranch, remotes)
		pendingConfirmation = .forcePush(remoteName: remoteName)
	}

	public func didRequestPushTags(remoteName: String) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			remotes.contains(where: { $0.name == remoteName })
		else { return }
		let referencesUseCase = dependencies.referencesUseCase
		requestNetworkResult(activity: .pushTags(remoteName)) {
			try await referencesUseCase.pushTags(
				remote: remoteName,
				at: repositoryURL
			)
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
		forcePushContext = nil
	}

	func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
		let context = forcePushContext
		pendingConfirmation = nil
		forcePushContext = nil
		switch confirmation {
		case .forcePush(let remoteName):
			guard let context, dependencies.repositoryURL() == context.repositoryURL,
				currentBranch?.name == context.branch.name, currentBranch?.hash == context.branch.hash,
				currentBranch?.upstream == context.branch.upstream
			else {
				actions.didReceiveError(
					"The repository or branch has changed. Review the branch before force pushing.")
				return
			}
			requestForcePush(remoteName: remoteName, expecting: context.branch, remotes: context.remotes)
		}
	}

	private func requestForcePush(
		remoteName: String?, expecting branch: GitBranch, remotes: [GitRemote]
	) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			pushAction != .unavailable
		else { return }
		let referencesUseCase = dependencies.referencesUseCase
		let operationState = operationState
		requestNetworkMutation(activity: .forcePush(branch.name)) {
			try await referencesUseCase.forcePush(
				currentBranch: branch,
				remotes: remotes,
				operationState: operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	private func requestNetworkMutation(
		activity: Activity,
		isAutomatic: Bool = false,
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot?
	) {
		requestNetworkResult(activity: activity, isAutomatic: isAutomatic) {
			try await RepositoryReferenceMutationResult(snapshot: operation())
		}
	}

	private func requestNetworkResult(
		activity: Activity,
		isAutomatic: Bool = false,
		_ operation: @escaping @MainActor () async throws -> RepositoryReferenceMutationResult
	) {
		guard !isLoading, let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		networkTask?.cancel()
		let requestID = beginNetworkRequest(activity: activity)
		isAutomaticFetch = isAutomatic
		networkTask = Task { [weak self] in
			defer { self?.finishNetworkRequest(id: requestID) }
			do {
				try Task.checkCancellation()
				let result = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeNetworkRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else { return }
				if isAutomatic {
					actions.didFetchAutomatically()
				} else if let snapshot = result.snapshot {
					actions.didProduceSnapshot(snapshot)
				}
				if let message = result.message { actions.didReceiveError(message) }
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeNetworkRequestID == requestID,
					self.dependencies.repositoryURL() == expectedRepositoryURL
				else {
					return
				}
				if isAutomatic {
					Self.logger.warning(
						"Automatic fetch failed: \(error.localizedDescription, privacy: .private)")
					actions.didFetchAutomatically()
				} else {
					actions.didReceiveError(error.localizedDescription)
					await restoreSnapshot(at: expectedRepositoryURL, requestID: requestID)
				}
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
		networkTask = nil
		activityPresentationTask?.cancel()
		activityPresentationTask = nil
		activeNetworkRequestID = nil
		activity = nil
		presentedActivity = nil
		isAutomaticFetch = false
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

	private func restoreSnapshot(at repositoryURL: URL, requestID: Int) async {
		if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(at: repositoryURL) {
			guard !Task.isCancelled, activeNetworkRequestID == requestID,
				dependencies.repositoryURL() == repositoryURL
			else { return }
			actions.didProduceSnapshot(snapshot)
		}
	}
}
