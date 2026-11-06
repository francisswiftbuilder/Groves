import Foundation

final class GitProcessOutputCollector: Sendable {
	private let collectionTask: Task<Data, Never>

	init(pipe: Pipe, label: String) {
		let handle = pipe.fileHandleForReading
		let queue = DispatchQueue(label: "io.github.francisswiftbuilder.Groves.\(label)")
		collectionTask = Task {
			await withCheckedContinuation { continuation in
				queue.async {
					continuation.resume(returning: handle.readDataToEndOfFile())
				}
			}
		}
	}

	func data() async -> Data {
		await collectionTask.value
	}
}
