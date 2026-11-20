import Darwin
import Foundation

final class GitProcessOutputCollector: @unchecked Sendable {
	private let source: DispatchSourceRead
	private let queue: DispatchQueue
	private var output = Data()

	init(pipe: Pipe, label: String) throws {
		let handle = pipe.fileHandleForReading
		let descriptor = handle.fileDescriptor
		guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		queue = DispatchQueue(label: "com.francisswiftbuilder.pluminon.\(label)")
		source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
		source.setEventHandler { [weak self] in
			guard let self else { return }
			self.drain(upTo: max(1, Int(self.source.data)))
		}
		source.setCancelHandler { try? handle.close() }
		source.resume()
	}

	deinit {
		source.cancel()
	}

	func finish() async -> Data {
		await withCheckedContinuation { continuation in
			queue.async { [self] in
				drain(upTo: 8 * 1024 * 1024)
				source.cancel()
				continuation.resume(returning: output)
			}
		}
	}

	private func drain(upTo budget: Int) {
		guard !source.isCancelled else { return }
		var buffer = [UInt8](repeating: 0, count: 64 * 1024)
		var consumed = 0
		while consumed < budget {
			let count = Darwin.read(Int32(source.handle), &buffer, min(buffer.count, budget - consumed))
			if count > 0 {
				output.append(contentsOf: buffer.prefix(count))
				consumed += count
			} else if count == 0 {
				source.cancel()
				return
			} else if errno != EINTR {
				if errno != EAGAIN && errno != EWOULDBLOCK { source.cancel() }
				return
			}
		}
	}
}
