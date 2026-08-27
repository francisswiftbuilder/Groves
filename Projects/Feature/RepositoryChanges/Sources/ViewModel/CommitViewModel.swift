import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class CommitViewModel: ObservableObject {
	@Published var subject = ""
	@Published var body = ""
	@Published private(set) var isAmendingCommit = false
	@Published public private(set) var isLoading = false

	private let dependencies: CommitViewModelDependencies
	private let actions: CommitViewModelActions
	private var changes: [WorkingTreeChange] = []
	private var commits: [GitCommit] = []
	private var operationState: RepositoryOperationState = .normal
	private var mutationTask: Task<Void, Never>?

	public init(
		dependencies: CommitViewModelDependencies,
		actions: CommitViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		mutationTask?.cancel()
	}

	var canCommit: Bool {
		!subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& (isAmendingCommit || changes.contains(where: \.isStaged))
			&& !operationState.isDetached
			&& !isLoading
	}

	var canAmendCommit: Bool {
		!commits.isEmpty && !operationState.isDetached && !isLoading
	}

	var hasStagedChanges: Bool {
		changes.contains(where: \.isStaged)
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		changes = snapshot.changes
		commits = snapshot.commits
		operationState = snapshot.operationState
		if commits.isEmpty, isAmendingCommit {
			setAmendingCommit(false)
		}
	}

	public func reset() {
		mutationTask?.cancel()
		mutationTask = nil
		subject = ""
		body = ""
		changes = []
		commits = []
		operationState = .normal
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
			!operationState.isDetached,
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
