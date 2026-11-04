import Foundation

public struct GitCommitPlan: Sendable {
	public enum Model: Sendable {
		case privateCloudCompute
		case onDevice
	}

	public let input: GitCommitPlanInput
	public var tasks: [GitCommitTask]
	public let model: Model

	public init(input: GitCommitPlanInput, tasks: [GitCommitTask], model: Model) {
		self.input = input
		self.tasks = tasks
		self.model = model
	}

	public var isValid: Bool {
		let ids = tasks.flatMap(\.unitIDs)
		return !tasks.isEmpty && tasks.allSatisfy { $0.hasValidMessage && !$0.unitIDs.isEmpty }
			&& Set(ids).count == ids.count && Set(ids) == Set(input.units.map(\.id))
	}
}
