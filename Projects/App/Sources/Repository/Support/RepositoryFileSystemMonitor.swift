import CoreServices
import Foundation

final class RepositoryFileSystemMonitor: @unchecked Sendable {
	private let continuation: AsyncStream<[String]>.Continuation
	private let queue: DispatchQueue
	private var stream: FSEventStreamRef?
	private var contextInfo: UnsafeMutableRawPointer?
	private var isStopped = false

	private init(
		continuation: AsyncStream<[String]>.Continuation,
		queue: DispatchQueue
	) {
		self.continuation = continuation
		self.queue = queue
	}

	static func events(
		at repositoryURL: URL,
		queue: DispatchQueue = DispatchQueue(
			label: "dev.trees.repository-file-system-monitor",
			qos: .utility
		)
	) -> AsyncStream<[String]> {
		AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
			let eventID = FSEventsGetCurrentEventId()
			let monitor = RepositoryFileSystemMonitor(
				continuation: continuation,
				queue: queue
			)
			continuation.onTermination = { @Sendable _ in
				monitor.stop()
			}
			monitor.start(at: repositoryURL, sinceWhen: eventID)
		}
	}

	private func start(
		at repositoryURL: URL,
		sinceWhen eventID: FSEventStreamEventId
	) {
		queue.async { [self] in
			startOnQueue(at: repositoryURL, sinceWhen: eventID)
		}
	}

	private func startOnQueue(
		at repositoryURL: URL,
		sinceWhen eventID: FSEventStreamEventId
	) {
		dispatchPrecondition(condition: .onQueue(queue))
		guard !isStopped else { return }

		let contextInfo = Unmanaged.passRetained(self).toOpaque()
		var context = FSEventStreamContext(
			version: 0,
			info: contextInfo,
			retain: nil,
			release: nil,
			copyDescription: nil
		)
		let flags = FSEventStreamCreateFlags(
			kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
		)

		guard
			let stream = FSEventStreamCreate(
				kCFAllocatorDefault,
				repositoryFileSystemEventCallback,
				&context,
				[repositoryURL.path] as CFArray,
				eventID,
				0.35,
				flags
			)
		else {
			Unmanaged<RepositoryFileSystemMonitor>.fromOpaque(contextInfo).release()
			isStopped = true
			continuation.finish()
			return
		}

		self.stream = stream
		self.contextInfo = contextInfo
		FSEventStreamSetDispatchQueue(stream, queue)

		guard FSEventStreamStart(stream) else {
			stopOnQueue()
			return
		}
	}

	private func stop() {
		queue.async { [self] in
			stopOnQueue()
		}
	}

	private func stopOnQueue() {
		dispatchPrecondition(condition: .onQueue(queue))
		guard !isStopped else { return }
		isStopped = true

		guard let stream, let contextInfo else {
			continuation.finish()
			return
		}

		self.stream = nil
		self.contextInfo = nil
		FSEventStreamStop(stream)
		FSEventStreamInvalidate(stream)
		FSEventStreamRelease(stream)
		Unmanaged<RepositoryFileSystemMonitor>.fromOpaque(contextInfo).release()
		continuation.finish()
	}

	func didReceiveEvents(at paths: [String]) {
		continuation.yield(paths)
	}
}

private func repositoryFileSystemEventCallback(
	_ stream: ConstFSEventStreamRef,
	_ contextInfo: UnsafeMutableRawPointer?,
	_ eventCount: Int,
	_ eventPaths: UnsafeMutableRawPointer,
	_ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
	_ eventIDs: UnsafePointer<FSEventStreamEventId>
) {
	guard eventCount > 0, let contextInfo else { return }
	let pathPointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
	let paths = (0..<eventCount).map { index in
		String(cString: pathPointers[index])
	}
	let monitor = Unmanaged<RepositoryFileSystemMonitor>
		.fromOpaque(contextInfo)
		.takeUnretainedValue()
	monitor.didReceiveEvents(at: paths)
}
