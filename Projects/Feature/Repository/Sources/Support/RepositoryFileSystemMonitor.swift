import CoreServices
import Foundation

final class RepositoryFileSystemMonitor: @unchecked Sendable {
	private let continuation: AsyncStream<Void>.Continuation
	private let queue = DispatchQueue(
		label: "dev.trees.repository-file-system-monitor",
		qos: .utility
	)
	private let lock = NSLock()
	private var stream: FSEventStreamRef?
	private var contextInfo: UnsafeMutableRawPointer?

	private init(continuation: AsyncStream<Void>.Continuation) {
		self.continuation = continuation
	}

	deinit {
		stop()
	}

	static func events(at repositoryURL: URL) -> AsyncStream<Void> {
		AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
			let monitor = RepositoryFileSystemMonitor(continuation: continuation)
			continuation.onTermination = { @Sendable _ in
				monitor.stop()
			}
			monitor.start(at: repositoryURL)
		}
	}

	private func start(at repositoryURL: URL) {
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
				FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
				0.35,
				flags
			)
		else {
			Unmanaged<RepositoryFileSystemMonitor>.fromOpaque(contextInfo).release()
			continuation.finish()
			return
		}

		lock.withLock {
			self.stream = stream
			self.contextInfo = contextInfo
		}
		FSEventStreamSetDispatchQueue(stream, queue)

		guard FSEventStreamStart(stream) else {
			stop()
			return
		}
	}

	private func stop() {
		let resources = lock.withLock { () -> (FSEventStreamRef, UnsafeMutableRawPointer)? in
			guard let stream, let contextInfo else { return nil }
			self.stream = nil
			self.contextInfo = nil
			return (stream, contextInfo)
		}

		guard let resources else { return }
		FSEventStreamStop(resources.0)
		FSEventStreamInvalidate(resources.0)
		FSEventStreamRelease(resources.0)
		Unmanaged<RepositoryFileSystemMonitor>.fromOpaque(resources.1).release()
		continuation.finish()
	}

	fileprivate func didReceiveEvents() {
		continuation.yield()
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
	let monitor = Unmanaged<RepositoryFileSystemMonitor>
		.fromOpaque(contextInfo)
		.takeUnretainedValue()
	monitor.didReceiveEvents()
}
