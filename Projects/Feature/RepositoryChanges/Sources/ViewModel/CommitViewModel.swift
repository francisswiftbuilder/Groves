import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class CommitViewModel: ObservableObject {
	public struct Actions {
		let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		let didReceiveError: @MainActor (String) -> Void
		let didChangeAmendingCommit: @MainActor (Bool) -> Void

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
		let contentUseCase: any RepositoryContentUseCase
		let changesUseCase: any RepositoryChangesUseCase
		let repositoryURL: @MainActor () -> URL?

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

	@Published var subject = ""
	@Published var body = ""
	@Published private(set) var isAmendingCommit = false
	@Published public private(set) var isLoading = false
	@Published private var availability = CommitAvailability.empty

	private let dependencies: Dependencies
	private let actions: Actions
	private var commits: [GitCommit] = []
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
		mutationTask?.cancel()
		mutationTask = nil
		subject = ""
		body = ""
		commits = []
		availability = .empty
		setAmendingCommit(false)
	}

	func didRequestCommit() {
		guard let repositoryURL = dependencies.repositoryURL(), canCommit else { return }
		let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedBody = body.trimmingCharacters(in: .newlines)
		let body =
			trimmedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? ""
			: trimmedBody
		let amend = isAmendingCommit
		requestMutation {
			let snapshot = try await self.dependencies.changesUseCase.commit(
				subject: subject,
				body: body,
				amend: amend,
				at: repositoryURL
			)
			self.subject = ""
			self.body = ""
			self.setAmendingCommit(false)
			return snapshot
		}
	}

	func didRequestAmendWithoutEditingMessage() {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			hasStagedChanges,
			!isDetached,
			!isLoading
		else { return }
		requestMutation {
			try await self.dependencies.changesUseCase.amendWithoutEditingMessage(
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
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				actions.didProduceSnapshot(snapshot)
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
