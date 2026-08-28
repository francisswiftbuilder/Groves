import Foundation

actor GitTestGate {
	private var continuation: CheckedContinuation<Void, Never>?
	private var isOpen = false

	func wait() async {
		if isOpen { return }
		await withCheckedContinuation { continuation in
			self.continuation = continuation
		}
	}

	func open() {
		isOpen = true
		continuation?.resume()
		continuation = nil
	}
}
