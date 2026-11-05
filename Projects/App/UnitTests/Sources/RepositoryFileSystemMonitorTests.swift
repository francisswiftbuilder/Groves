import CoreServices
import DomainGitInterface
import Foundation
import Testing

@testable import Groves

struct RepositoryFileSystemMonitorTests {
	@Test
	func worktreeEventsIncludeItsPrivateIndexAndSharedReferences() async throws {
		let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
			.appending(path: "GrovesWorktreeMonitor-\(UUID())", directoryHint: .isDirectory)
		let worktree = directory.appending(path: "topic", directoryHint: .isDirectory)
		let common = directory.appending(path: "main.git", directoryHint: .isDirectory)
		let metadata = common.appending(path: "worktrees/topic", directoryHint: .isDirectory)
		let refs = common.appending(path: "refs/heads", directoryHint: .isDirectory)
		for url in [worktree, metadata, refs] {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		}
		defer { try? FileManager.default.removeItem(at: directory) }
		try Data("gitdir: ../main.git/worktrees/topic\n".utf8).write(
			to: worktree.appending(path: ".git"))
		try Data("../..\n".utf8).write(to: metadata.appending(path: "commondir"))
		let index = metadata.appending(path: "index")
		let branch = refs.appending(path: "main")
		#expect(
			Set(RepositoryFileSystemMonitor.gitDirectories(at: worktree).map(\.path)) == [
				metadata.path, common.path,
			])
		let queue = DispatchQueue(label: "dev.groves.worktree-monitor-tests")
		let events = RepositoryFileSystemMonitor.events(at: worktree, queue: queue)
		let received = Task {
			var seen: Set<String> = []
			for await paths in events {
				seen.formUnion(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
				if seen.contains(index.path), seen.contains(branch.path) { return seen }
			}
			return seen
		}
		let timeout = Task {
			try await Task.sleep(for: .seconds(3))
			received.cancel()
		}
		defer {
			received.cancel()
			timeout.cancel()
		}
		queue.sync {}
		try Data("index".utf8).write(to: index)
		try Data("ref".utf8).write(to: branch)
		let paths = await received.value
		#expect(paths.contains(index.path))
		#expect(paths.contains(branch.path))
	}

	@Test(
		arguments: [
			kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
			kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged,
			kFSEventStreamEventFlagEventIdsWrapped,
		])
	func systemRescanFlagsInvalidateTheWorkingTree(flag: Int) async {
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		let monitor = RepositoryFileSystemMonitor(
			continuation: continuation, queue: DispatchQueue(label: "dev.groves.rescan-tests"),
			repositoryURL: URL(fileURLWithPath: "/repo"))
		monitor.didReceiveEvents(at: ["/repo/.git/objects"], flags: [FSEventStreamEventFlags(flag)])
		var iterator = events.makeAsyncIterator()
		let paths = await iterator.next()
		#expect(paths?.contains("/repo") == true)
		continuation.finish()
	}

	@Test
	func bufferedBatchesPreserveEarlierFileChanges() async {
		let (events, continuation) = AsyncStream<[String]>.makeStream(
			bufferingPolicy: .bufferingNewest(1))
		let monitor = RepositoryFileSystemMonitor(
			continuation: continuation, queue: DispatchQueue(label: "dev.groves.monitor-buffer-test"))
		monitor.didReceiveEvents(at: ["/repo/Source.swift"])
		monitor.didReceiveEvents(at: ["/repo/.git/index"])
		monitor.didReceiveEvents(at: ["/repo/.git/FETCH_HEAD"])
		var iterator = events.makeAsyncIterator()
		let paths = await iterator.next()
		#expect(
			Set(paths ?? []) == ["/repo/Source.swift", "/repo/.git/index", "/repo/.git/FETCH_HEAD"])
		continuation.finish()
	}

	@Test
	func testEventsReturnsWhileStartupQueueIsSuspended() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let startupQueue = DispatchQueue(label: "dev.groves.repository-monitor-tests")
		startupQueue.suspend()
		let start = ContinuousClock.now
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: startupQueue
		)
		let elapsed = start.duration(to: .now)
		startupQueue.resume()

		#expect(elapsed < .milliseconds(100))

		let eventTask = Task {
			for await _ in events {}
		}
		eventTask.cancel()
		await eventTask.value
		startupQueue.sync {}
	}

	@Test
	func testEventsEmitsWhenNestedFileChanges() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		let nestedDirectoryURL = directoryURL.appending(path: "Nested", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: nestedDirectoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let monitorQueue = DispatchQueue(label: "dev.groves.repository-monitor-event-tests")
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: monitorQueue
		)
		try await confirmation("Receives a recursive file system event") { eventReceived in
			let eventTask = Task {
				for await paths in events {
					let expectedDirectoryPath = directoryURL.standardizedFileURL.path
					#expect(
						paths.contains {
							URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(expectedDirectoryPath)
						})
					eventReceived()
					return
				}
			}
			let timeoutTask = Task {
				try await Task.sleep(for: .seconds(3))
				eventTask.cancel()
			}
			defer {
				eventTask.cancel()
				timeoutTask.cancel()
			}
			monitorQueue.sync {}
			try Data("updated".utf8).write(to: nestedDirectoryURL.appending(path: "File.txt"))
			await eventTask.value
		}
		monitorQueue.sync {}
	}
}
