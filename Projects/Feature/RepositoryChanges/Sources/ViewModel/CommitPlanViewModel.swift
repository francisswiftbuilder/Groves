import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class CommitPlanViewModel {
	public struct Dependencies {
		let useCase: any RepositoryCommitPlanningUseCase
		let contentUseCase: any RepositoryContentUseCase
		let repositoryURL: @MainActor () -> URL?

		public init(
			useCase: any RepositoryCommitPlanningUseCase,
			contentUseCase: any RepositoryContentUseCase,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.useCase = useCase
			self.contentUseCase = contentUseCase
			self.repositoryURL = repositoryURL
		}
	}

	var isPresented = false
	private(set) var plan: GitCommitPlan?
	private(set) var isGenerating = false
	private(set) var analysisProgress: CommitAnalysisProgress?
	private(set) var isCommitting = false
	private(set) var errorMessage: String?
	private(set) var completedCount = 0
	private(set) var needsRefresh = false
	private(set) var canGenerate = false
	var selectedTaskID: UUID?
	var selectedUnitID: String?

	private let dependencies: Dependencies
	private let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	@ObservationIgnored private var task: Task<Void, Never>?
	private var requestID: UUID?

	public init(
		dependencies: Dependencies,
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void
	) {
		self.dependencies = dependencies
		self.didProduceSnapshot = didProduceSnapshot
	}

	deinit { task?.cancel() }

	var isBusy: Bool { isGenerating || isCommitting }
	var tasks: [GitCommitTask] { plan?.tasks ?? [] }
	var selectedTask: GitCommitTask? { tasks.first { $0.id == selectedTaskID } }
	var selectedUnits: [GitCommitUnit] {
		guard let selectedTask else { return [] }
		return plan?.input.units.filter { selectedTask.unitIDs.contains($0.id) } ?? []
	}
	var selectedUnit: GitCommitUnit? {
		selectedUnits.first { $0.id == selectedUnitID } ?? selectedUnits.first
	}
	var canCommit: Bool {
		!isBusy && !needsRefresh && plan?.isValid == true && selectedTask != nil
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		canGenerate =
			snapshot.changes.contains(where: \.isStaged)
			&& snapshot.operationState.isIdle && !snapshot.operationState.isDetached
	}

	func didPresent() {
		guard canGenerate, !isBusy else { return }
		isPresented = true
		completedCount = 0
		didRequestPlan()
	}

	func didRequestPlan() {
		guard let url = dependencies.repositoryURL(), !isBusy else { return }
		let id = UUID()
		requestID = id
		isGenerating = true
		analysisProgress = nil
		errorMessage = nil
		needsRefresh = false
		plan = nil
		let useCase = dependencies.useCase
		task = Task { [weak self] in
			defer { self?.finishRequest(id) }
			do {
				let plan = try await useCase.loadPlan(at: url) { [weak self] progress in
					await self?.didUpdateProgress(progress, request: id)
				}
				try Task.checkCancellation()
				guard let self, requestID == id, dependencies.repositoryURL() == url else { return }
				self.plan = plan
				selectedTaskID = plan.tasks.first?.id
				selectedUnitID = nil
			} catch {
				guard let self, !Task.isCancelled, requestID == id else { return }
				errorMessage = error.localizedDescription
			}
		}
	}

	func didUpdateSubject(_ value: String) {
		guard !isBusy, let index = plan?.tasks.firstIndex(where: { $0.id == selectedTaskID }) else {
			return
		}
		plan?.tasks[index].subject = value
	}

	func didUpdateBody(_ value: String) {
		guard !isBusy, let index = plan?.tasks.firstIndex(where: { $0.id == selectedTaskID }) else {
			return
		}
		plan?.tasks[index].body = value
	}

	func didMoveSelectedUnit(to taskID: UUID?) {
		guard !isBusy, let unit = selectedUnit, var plan,
			let source = plan.tasks.firstIndex(where: { $0.id == selectedTaskID }),
			taskID != selectedTaskID
		else { return }
		if let taskID {
			guard let destination = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
			plan.tasks[destination].unitIDs.append(unit.id)
		} else {
			plan.tasks.append(GitCommitTask(subject: "", body: "", unitIDs: [unit.id]))
		}
		plan.tasks[source].unitIDs.removeAll { $0 == unit.id }
		plan.tasks.removeAll { $0.unitIDs.isEmpty }
		self.plan = plan
		if selectedTask == nil { selectedTaskID = plan.tasks.first?.id }
		selectedUnitID = nil
	}

	func didRequestCommit() {
		guard canCommit, let submitted = selectedTask, let plan,
			let url = dependencies.repositoryURL()
		else { return }
		let id = UUID()
		requestID = id
		isCommitting = true
		errorMessage = nil
		let dependencies = dependencies
		task = Task { [weak self] in
			defer { self?.finishRequest(id) }
			do {
				let input = try await dependencies.useCase.commit(submitted, from: plan, at: url)
				try Task.checkCancellation()
				guard let self, requestID == id, dependencies.repositoryURL() == url else { return }
				completedCount += 1
				let remaining = plan.tasks.filter { $0.id != submitted.id }
				let next = GitCommitPlan(input: input, tasks: remaining, model: plan.model)
				self.plan = next
				selectedTaskID = remaining.first?.id
				selectedUnitID = nil
				if !remaining.isEmpty, !next.isValid {
					needsRefresh = true
					errorMessage = GitCommitPlanError.repositoryChanged.localizedDescription
				}
				let snapshot = try await dependencies.contentUseCase.loadSnapshot(at: url)
				guard !Task.isCancelled, requestID == id else { return }
				didProduceSnapshot(snapshot)
			} catch {
				guard let self, !Task.isCancelled, requestID == id else { return }
				errorMessage = error.localizedDescription
				if let error = error as? GitCommitPlanError, case .repositoryChanged = error {
					needsRefresh = true
				}
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(at: url) {
					guard !Task.isCancelled, requestID == id else { return }
					didProduceSnapshot(snapshot)
				}
			}
		}
	}

	public func onDisappear() {
		task?.cancel()
		task = nil
		requestID = nil
		isGenerating = false
		isCommitting = false
		isPresented = false
		analysisProgress = nil
	}

	private func didUpdateProgress(_ progress: CommitAnalysisProgress, request: UUID) {
		guard requestID == request, isGenerating else { return }
		analysisProgress = progress
	}

	private func finishRequest(_ id: UUID) {
		guard requestID == id else { return }
		task = nil
		requestID = nil
		isGenerating = false
		isCommitting = false
	}
}
