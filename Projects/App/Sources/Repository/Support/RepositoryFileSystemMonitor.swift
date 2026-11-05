import CoreServices
import Foundation

final class RepositoryFileSystemMonitor: @unchecked Sendable {
	private let continuation: AsyncStream<[String]>.Continuation
	private let queue: DispatchQueue
	private var stream: FSEventStreamRef?
	private var contextInfo: UnsafeMutableRawPointer?
	private var isStopped = false
	private var repositoryURL: URL?
	private var monitoredPaths: [String] = []

	init(
		continuation: AsyncStream<[String]>.Continuation,
		queue: DispatchQueue,
		repositoryURL: URL? = nil
	) {
		self.continuation = continuation
		self.queue = queue
		self.repositoryURL = repositoryURL
	}

	static func events(
		at repositoryURL: URL,
		queue: DispatchQueue = DispatchQueue(
			label: "dev.groves.repository-file-system-monitor",
			qos: .utility
		)
	) -> AsyncStream<[String]> {
		AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
			let eventID = FSEventsGetCurrentEventId()
			let monitor = RepositoryFileSystemMonitor(
				continuation: continuation,
				queue: queue,
				repositoryURL: repositoryURL
			)
			continuation.onTermination = { @Sendable _ in
				monitor.stop()
			}
			monitor.start(at: repositoryURL, sinceWhen: eventID)
		}
	}

	static func gitDirectories(at repositoryURL: URL) -> [URL] {
		let root = URL(fileURLWithPath: repositoryURL.path, isDirectory: true)
		let dotGit = root.appending(path: ".git")
		var gitDirectory = URL(fileURLWithPath: dotGit.path, isDirectory: true)
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory),
			!isDirectory.boolValue,
			let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
			pointer.hasPrefix("gitdir: ")
		{
			let path = String(pointer.dropFirst(8)).trimmingCharacters(in: .newlines)
			if !path.isEmpty {
				gitDirectory = URL(fileURLWithPath: path, isDirectory: true, relativeTo: root)
			}
		}
		gitDirectory = gitDirectory.standardizedFileURL.resolvingSymlinksInPath()
		var directories = [gitDirectory]
		if let commonPath = try? String(
			contentsOf: gitDirectory.appending(path: "commondir"), encoding: .utf8
		)
		.trimmingCharacters(in: .newlines), !commonPath.isEmpty {
			let common = URL(fileURLWithPath: commonPath, isDirectory: true, relativeTo: gitDirectory)
				.standardizedFileURL.resolvingSymlinksInPath()
			if common != gitDirectory { directories.append(common) }
		}
		return directories
	}

	private static func pathsToWatch(at repositoryURL: URL) -> [String] {
		let root = repositoryURL.resolvingSymlinksInPath().path
		let metadataPaths = gitDirectories(at: repositoryURL).map(\.path)
			.filter { FileManager.default.fileExists(atPath: $0) }
		let paths = Set([root] + metadataPaths)
		return paths.filter { path in
			!paths.contains { $0 != path && path.hasPrefix($0 + "/") }
		}.sorted()
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
		self.repositoryURL = repositoryURL
		monitoredPaths = Self.pathsToWatch(at: repositoryURL)

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
				monitoredPaths as CFArray,
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

	func didReceiveEvents(at paths: [String], flags: [FSEventStreamEventFlags] = []) {
		let rescanMask = FSEventStreamEventFlags(
			kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
				| kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
				| kFSEventStreamEventFlagEventIdsWrapped)
		var paths = paths
		if flags.contains(where: { $0 & rescanMask != 0 }), let repositoryURL {
			paths.append(repositoryURL.standardizedFileURL.path)
		}
		if case .dropped(let pendingPaths) = continuation.yield(paths) {
			continuation.yield(Array(Set(pendingPaths + paths)))
		}
		let restartMask = FSEventStreamEventFlags(
			kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped)
		if flags.contains(where: { $0 & restartMask != 0 }) {
			continuation.finish()
		}
		if let repositoryURL,
			paths.contains(where: {
				let path = URL(fileURLWithPath: $0).standardizedFileURL.path
				return path == repositoryURL.appending(path: ".git").standardizedFileURL.path
					|| path.hasSuffix("/commondir")
			}), Self.pathsToWatch(at: repositoryURL) != monitoredPaths
		{
			continuation.finish()
		}
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
	monitor.didReceiveEvents(
		at: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: eventCount)))
}
