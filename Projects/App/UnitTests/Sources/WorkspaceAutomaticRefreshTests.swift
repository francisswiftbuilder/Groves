import DomainGitInterface
import Foundation
import Synchronization
import Testing

@testable import Groves

@MainActor
struct WorkspaceAutomaticRefreshTests {
	private actor ContentStub: RepositoryContentUseCase {
		let gate: GitDiffGate
		var revision = 1
		var failures = 0

		init(gate: GitDiffGate = GitDiffGate()) { self.gate = gate }

		func update(revision: Int, failures: Int = 0) {
			self.revision = revision
			self.failures = failures
		}

		func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot {
			let revision = revision
			let fails = failures > 0
			if fails { failures -= 1 }
			await gate.enter("snapshot")
			if fails { throw GitRepositoryError.commandFailed("Temporary repository read failure") }
			return .init(
				changes: [
					.init(
						path: "Revision\(revision).swift", previousPath: nil, indexState: .unchanged,
						workingTreeState: .modified)
				],
				amendChanges: [], commits: [], branches: [], remotes: [], operationState: .normal,
				tags: [], stashes: [], fileTree: [])
		}

		func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data { Data() }
	}

	@Test
	func busyWorkspaceRetainsTheLastFileChange() async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var canRefresh = true
		var paths: [String] = []
		let model = makeModel(
			content: content, events: events, canRefresh: { canRefresh },
			receive: { paths = $0.changes.map(\.path) })
		defer {
			model.onDisappear()
			continuation.finish()
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		canRefresh = false
		await content.update(revision: 2)
		continuation.yield(["/repo/Source.swift"])
		try await Task.sleep(for: .milliseconds(650))
		#expect(paths == ["Revision1.swift"])
		canRefresh = true
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	@Test
	func eventDuringTheInitialLoadIsReplayedAfterLoadingFinishes() async throws {
		let gate = GitDiffGate(suspendsRequests: true)
		let content = ContentStub(gate: gate)
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var paths: [String] = []
		let model = makeModel(content: content, events: events) { paths = $0.changes.map(\.path) }
		defer {
			model.onDisappear()
			continuation.finish()
			Task { for index in 0..<5 { await gate.resumeCall(index) } }
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { await gate.totalCallCount() == 1 }
		await content.update(revision: 2)
		continuation.yield(["/repo/Source.swift"])
		try await Task.sleep(for: .milliseconds(650))
		await gate.resumeCall(0)
		try await waitUntil { await gate.totalCallCount() == 2 }
		await gate.resumeCall(1)
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	@Test
	func newEventsDoNotCancelTheSnapshotBeingRead() async throws {
		let gate = GitDiffGate(suspendsRequests: true)
		await gate.resumeCall(0)
		let content = ContentStub(gate: gate)
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var paths: [String] = []
		let model = makeModel(content: content, events: events) { paths = $0.changes.map(\.path) }
		defer {
			model.onDisappear()
			continuation.finish()
			Task { for index in 0..<5 { await gate.resumeCall(index) } }
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		await content.update(revision: 2)
		continuation.yield(["/repo/Source.swift"])
		try await waitUntil { await gate.totalCallCount() == 2 }
		await content.update(revision: 3)
		continuation.yield(["/repo/Another.swift"])
		try await Task.sleep(for: .milliseconds(650))
		#expect(await gate.totalCallCount() == 2)
		await gate.resumeCall(1)
		try await waitUntil { paths == ["Revision2.swift"] }
		try await waitUntil { await gate.totalCallCount() == 3 }
		await gate.resumeCall(2)
		try await waitUntil { paths == ["Revision3.swift"] }
	}

	@Test(
		arguments: [
			"index", "HEAD", "refs/heads/main", "packed-refs", "FETCH_HEAD", "refs/remotes/origin/main",
			"refs/tags/v1.0.0",
		])
	func gitMetadataRevalidatesDiffOnlyWhenItsBaseCanChange(path: String) async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var revalidations: [Bool] = []
		let model = makeModel(
			content: content, events: events, revalidate: { revalidations.append($0) }, receive: { _ in })
		defer {
			model.onDisappear()
			continuation.finish()
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { revalidations.count == 1 }
		continuation.yield(["/repo/.git/\(path)"])
		try await waitUntil { revalidations.count == 2 }
		#expect(
			revalidations.last == ["index", "HEAD", "refs/heads/main", "packed-refs"].contains(path))
	}

	@Test
	func transientReadFailureRetriesWithoutAnotherFileEvent() async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var paths: [String] = []
		let model = makeModel(content: content, events: events) { paths = $0.changes.map(\.path) }
		defer {
			model.onDisappear()
			continuation.finish()
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		await content.update(revision: 2, failures: 1)
		continuation.yield(["/repo/Source.swift"])
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	@Test
	func exhaustedRetriesStopUntilAnotherEventArrives() async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var paths: [String] = []
		let model = makeModel(content: content, events: events) { paths = $0.changes.map(\.path) }
		defer {
			model.onDisappear()
			continuation.finish()
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		await content.update(revision: 2, failures: 3)
		continuation.yield(["/repo/Source.swift"])
		try await waitUntil { await content.gate.totalCallCount() == 4 }
		try await Task.sleep(for: .milliseconds(650))
		#expect(await content.gate.totalCallCount() == 4)
		#expect(paths == ["Revision1.swift"])
		continuation.yield(["/repo/Source.swift"])
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	@Test
	func waitingForAnIdleWorkspaceDoesNotRetainTheModel() async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var canRefresh = true
		var paths: [String] = []
		var model: WorkspaceViewModel? = makeModel(
			content: content, events: events, canRefresh: { canRefresh },
			receive: { paths = $0.changes.map(\.path) })
		defer { continuation.finish() }
		model?.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		canRefresh = false
		continuation.yield(["/repo/Source.swift"])
		try await Task.sleep(for: .milliseconds(650))
		weak var reference = model
		model = nil
		try await waitUntil { reference == nil }
	}

	@Test
	func firstActivationRevalidatesContentThatWasLoadedInTheBackground() async throws {
		let content = ContentStub()
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var paths: [String] = []
		let model = makeModel(content: content, events: events) { paths = $0.changes.map(\.path) }
		defer {
			model.onDisappear()
			continuation.finish()
		}
		model.didProduceSnapshot(try await content.loadSnapshot(at: URL(fileURLWithPath: "/repo")))
		model.onAppear(isSceneActive: false)
		await content.update(revision: 2)
		model.didChangeSceneActivation(true)
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	@Test(arguments: [false, true])
	func olderAutomaticReadCannotOverwriteANewerMutation(partialMutation: Bool) async throws {
		let gate = GitDiffGate(suspendsRequests: true)
		await gate.resumeCall(0)
		let content = ContentStub(gate: gate)
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var received: [String] = []
		let model = makeModel(content: content, events: events) {
			received.append(contentsOf: $0.changes.map(\.path))
		}
		defer {
			model.onDisappear()
			continuation.finish()
			Task { for index in 0..<6 { await gate.resumeCall(index) } }
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { received == ["Revision1.swift"] }
		await content.update(revision: 2)
		continuation.yield(["/repo/Source.swift"])
		try await waitUntil { await gate.totalCallCount() == 2 }
		await content.update(revision: 3)
		if partialMutation {
			model.didApplyDiffMutation()
		} else {
			await gate.resumeCall(2)
			model.didProduceSnapshot(try await content.loadSnapshot(at: URL(fileURLWithPath: "/repo")))
		}
		await gate.resumeCall(1)
		let nextRead = partialMutation ? 2 : 3
		try await waitUntil { await gate.totalCallCount() == nextRead + 1 }
		await gate.resumeCall(nextRead)
		try await waitUntil { received.last == "Revision3.swift" }
		#expect(!received.contains("Revision2.swift"))
	}

	@Test
	func manualRefreshDoesNotOverwriteANewerMutationSnapshot() async throws {
		let gate = GitDiffGate(suspendsRequests: true)
		await gate.resumeCall(0)
		let content = ContentStub(gate: gate)
		let (events, continuation) = AsyncStream<[String]>.makeStream()
		var received: [String] = []
		let model = makeModel(content: content, events: events) {
			received.append(contentsOf: $0.changes.map(\.path))
		}
		defer {
			model.onDisappear()
			continuation.finish()
			Task { for index in 0..<6 { await gate.resumeCall(index) } }
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { received == ["Revision1.swift"] }
		await content.update(revision: 2)
		model.didRequestRefresh()
		try await waitUntil { await gate.totalCallCount() == 2 }
		await content.update(revision: 3)
		await gate.resumeCall(2)
		model.didProduceSnapshot(try await content.loadSnapshot(at: URL(fileURLWithPath: "/repo")))
		await gate.resumeCall(1)
		try await waitUntil { !model.isLoading }
		#expect(!received.contains("Revision2.swift"))
	}

	@Test
	func finishedMonitorReconnectsWithoutReactivatingTheWindow() async throws {
		let content = ContentStub()
		let first = AsyncStream<[String]>.makeStream()
		let second = AsyncStream<[String]>.makeStream()
		let calls = Mutex(0)
		var paths: [String] = []
		let model = makeModel(
			content: content, events: first.stream,
			eventSource: { _ in
				calls.withLock {
					$0 += 1
					return $0 == 1 ? first.stream : second.stream
				}
			}, receive: { paths = $0.changes.map(\.path) })
		defer {
			model.onDisappear()
			first.continuation.finish()
			second.continuation.finish()
		}
		model.onAppear(isSceneActive: true)
		try await waitUntil { paths == ["Revision1.swift"] }
		first.continuation.finish()
		try await waitUntil { calls.withLock { $0 >= 2 } }
		await content.update(revision: 2)
		second.continuation.yield(["/repo/Updated.swift"])
		try await waitUntil { paths == ["Revision2.swift"] }
	}

	private func makeModel(
		content: ContentStub, events: AsyncStream<[String]>,
		canRefresh: @escaping @MainActor () -> Bool = { true },
		revalidate: @escaping @MainActor (Bool) -> Void = { _ in },
		eventSource: (@Sendable (URL) -> AsyncStream<[String]>)? = nil,
		receive: @escaping @MainActor (RepositorySnapshot) -> Void
	) -> WorkspaceViewModel {
		WorkspaceViewModel(
			dependencies: .init(
				contentUseCase: content, canAutomaticallyRefresh: canRefresh,
				fileSystemEvents: eventSource ?? { _ in events }),
			actions: .init(
				resetContent: {},
				distributeSnapshot: { snapshot, _, revalidates in
					receive(snapshot)
					revalidate(revalidates)
				}, refreshDiffPresentation: {}, focusConflict: { _ in }, activateSidebarSelection: { _ in }),
			repositoryURL: URL(fileURLWithPath: "/repo"))
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(3))
		while await !condition() {
			guard ContinuousClock.now < deadline else {
				Issue.record("Timed out waiting for automatic refresh")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
