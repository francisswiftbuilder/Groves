import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class CommitViewModel {
	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void
		public let didChangeAmendingCommit: @MainActor (Bool) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void,
			didChangeAmendingCommit: @escaping @MainActor (Bool) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
			self.didChangeAmendingCommit = didChangeAmendingCommit
		}
	}

	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase
		public let changesUseCase: any RepositoryChangesUseCase
		public let repositoryURL: @MainActor () -> URL?

		public init(
			contentUseCase: any RepositoryContentUseCase,
			changesUseCase: any RepositoryChangesUseCase,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.contentUseCase = contentUseCase
			self.changesUseCase = changesUseCase
			self.repositoryURL = repositoryURL
		}
	}

	var subject = ""
	var body = ""
	private(set) var isAmendingCommit = false
	public private(set) var isLoading = false
	private var availability = CommitAvailability.empty

	private let dependencies: Dependencies
	private let actions: Actions
	private var commits: [GitCommit] = []
	@ObservationIgnored private var mutationTask: Task<Void, Never>?
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0

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

	var hasStagedChanges: Bool {
		availability.hasStagedChanges
	}

	var hasCommits: Bool {
		availability.hasCommits
	}

	var isDetached: Bool {
		availability.isDetached
	}

	var canCommit: Bool {
		!subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& (isAmendingCommit || hasStagedChanges)
			&& !isDetached
			&& !isLoading
	}

	var canAmendCommit: Bool {
		hasCommits && !isDetached && !isLoading
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		let nextAvailability = CommitAvailability(
			hasStagedChanges: snapshot.changes.contains(where: \.isStaged),
			hasCommits: !snapshot.commits.isEmpty,
			isDetached: snapshot.operationState.isDetached
		)
		if availability != nextAvailability {
			availability = nextAvailability
		}
		commits = snapshot.commits
		if commits.isEmpty, isAmendingCommit {
			setAmendingCommit(false)
		}
	}

	public func reset() {
		onDisappear()
		subject = ""
		body = ""
		commits = []
		availability = .empty
		setAmendingCommit(false)
	}

	public func onDisappear() {
		mutationTask?.cancel()
		mutationTask = nil
		activeMutationRequestID = nil
		isLoading = false
	}

	func didRequestCommit() {
		guard let repositoryURL = dependencies.repositoryURL(), canCommit else { return }
		let submittedSubject = subject
		let submittedBody = body
		let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedBody = body.trimmingCharacters(in: .newlines)
		let body =
			trimmedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? ""
			: trimmedBody
		let amend = isAmendingCommit
		let changesUseCase = dependencies.changesUseCase
		requestMutation {
			try await changesUseCase.commit(
				subject: subject,
				body: body,
				amend: amend,
				at: repositoryURL
			)
		} didSucceed: { [weak self] in
			guard let self else { return }
			if self.subject == submittedSubject, self.body == submittedBody {
				self.subject = ""
				self.body = ""
			}
			self.setAmendingCommit(false)
		}
	}

	func didRequestAmendWithoutEditingMessage() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			hasStagedChanges,
			canAmendCommit
		else { return }
		let changesUseCase = dependencies.changesUseCase
		requestMutation {
			try await changesUseCase.amendWithoutEditingMessage(
				at: repositoryURL
			)
		}
	}

	func didSetAmendingCommit(_ isAmending: Bool) {
		guard !isAmending || canAmendCommit else { return }
		setAmendingCommit(isAmending)
		if isAmending, subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			subject = currentCommit?.subject ?? ""
		}
		if isAmending, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			body = currentCommit?.body ?? ""
		}
	}

	private var currentCommit: GitCommit? {
		commits.first {
			$0.references.contains { reference in
				reference == "HEAD" || reference.hasPrefix("HEAD -> ")
			}
		} ?? commits.first
	}

	private func setAmendingCommit(_ isAmending: Bool) {
		guard isAmendingCommit != isAmending else { return }
		isAmendingCommit = isAmending
		actions.didChangeAmendingCommit(isAmending)
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot,
		didSucceed: @escaping @MainActor () -> Void = {}
	) {
		guard !isLoading, let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				try Task.checkCancellation()
				let snapshot = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeMutationRequestID == requestID else { return }
				didSucceed()
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeMutationRequestID == requestID else {
					return
				}
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: expectedRepositoryURL
				) {
					guard !Task.isCancelled, activeMutationRequestID == requestID else { return }
					actions.didProduceSnapshot(snapshot)
				}
			}
		}
	}

	private func beginMutation() -> Int {
		mutationRequestSequence += 1
		activeMutationRequestID = mutationRequestSequence
		isLoading = true
		return mutationRequestSequence
	}

	private func finishMutation(id: Int) {
		guard activeMutationRequestID == id else { return }
		activeMutationRequestID = nil
		mutationTask = nil
		isLoading = false
	}
}
