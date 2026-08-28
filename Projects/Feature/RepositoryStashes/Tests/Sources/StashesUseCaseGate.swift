import Foundation

actor StashesUseCaseGate {
	private var pendingCalls: [Int: CheckedContinuation<Void, Never>] = [:]
	private var resumedCalls: Set<Int> = []
	private var totalCalls = 0
	private let suspendsRequests: Bool

	init(suspendsRequests: Bool = false) {
		self.suspendsRequests = suspendsRequests
	}

	func enter() async {
		let index = totalCalls
		totalCalls += 1
		guard suspendsRequests, resumedCalls.contains(index) == false else { return }
		await withCheckedContinuation { continuation in
			pendingCalls[index] = continuation
		}
	}

	func resumeCall(_ index: Int) {
		resumedCalls.insert(index)
		pendingCalls[index]?.resume()
		pendingCalls[index] = nil
	}

	func callCount() -> Int {
		totalCalls
	}
}
