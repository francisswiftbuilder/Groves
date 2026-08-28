import Foundation

actor GitDiffGate {
	private var calls: [String] = []
	private var pendingCalls: [Int: CheckedContinuation<Void, Never>] = [:]
	private var resumedCalls: Set<Int> = []
	private let suspendsRequests: Bool

	init(suspendsRequests: Bool = false) {
		self.suspendsRequests = suspendsRequests
	}

	func enter(_ label: String) async {
		calls.append(label)
		let index = calls.count - 1
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

	func callCount(of label: String) -> Int {
		calls.filter { $0 == label }.count
	}

	func totalCallCount() -> Int {
		calls.count
	}
}
