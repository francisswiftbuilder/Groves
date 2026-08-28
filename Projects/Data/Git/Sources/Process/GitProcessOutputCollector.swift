import Foundation

final class GitProcessOutputCollector: @unchecked Sendable {
	private let handle: FileHandle
	private let group = DispatchGroup()
	private var collected = Data()

	init(pipe: Pipe, label: String) {
		handle = pipe.fileHandleForReading
		let queue = DispatchQueue(label: "io.github.francisswiftbuilder.Trees.\(label)")
		group.enter()
		queue.async { [self] in
			defer { group.leave() }
			collected = handle.readDataToEndOfFile()
		}
	}

	func data() async -> Data {
		await withCheckedContinuation { continuation in
			group.notify(queue: .global(qos: .userInitiated)) {
				continuation.resume(returning: self.collected)
			}
		}
	}
}
