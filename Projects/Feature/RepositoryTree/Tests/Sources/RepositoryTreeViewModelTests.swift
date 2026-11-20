import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryTree

@MainActor
struct RepositoryTreeViewModelTests {
	private actor Content: RepositoryContentUseCase {
		private(set) var paths: [String] = []
		var count: Int { paths.count }
		private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

		func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot { fatalError() }
		func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
			let id = paths.count
			paths.append(path)
			return try await withCheckedThrowingContinuation { pending[id] = $0 }
		}
		func resume(_ id: Int, with result: Result<Data, Error>) {
			pending.removeValue(forKey: id)?.resume(with: result)
		}
	}

	@Test
	func resetRemovesThePreviousRepositoriesFiles() {
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: Content()))
		model.apply(snapshot(), repositoryURL: URL(fileURLWithPath: "/first"))
		#expect(!model.fileTree.isEmpty)
		model.reset()
		#expect(model.fileTree.isEmpty)
		#expect(model.visibleTreeItems.isEmpty)
		#expect(model.fileCount == 0)
	}

	@Test
	func aFileThatCanNoLongerBeReadDoesNotKeepItsPreviousPreview() async throws {
		let content = Content()
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: content))
		defer { model.onDisappear() }
		let url = URL(fileURLWithPath: "/repo")
		model.apply(snapshot(), repositoryURL: url)
		model.didSelectTreeNode(id: "Value.swift")
		try await waitUntil { await content.count == 1 }
		let data = Data("old preview".utf8)
		await content.resume(0, with: .success(data))
		try await waitUntil {
			model.filePreview == .text(content: "old preview", byteCount: data.count)
		}

		model.apply(snapshot(), repositoryURL: url)
		try await waitUntil { await content.count == 2 }
		await content.resume(1, with: .failure(GitRepositoryError.fileUnavailable))
		try await waitUntil {
			model.filePreview == .failure(GitRepositoryError.fileUnavailable.localizedDescription)
		}
	}

	@Test
	func cancelledPreviewFailureCannotReplaceANewerPreviewOfTheSameFile() async throws {
		let content = Content()
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: content))
		defer { model.onDisappear() }
		let url = URL(fileURLWithPath: "/repo")
		model.apply(snapshot(), repositoryURL: url)
		model.didSelectTreeNode(id: "Value.swift")
		try await waitUntil { await content.count == 1 }
		model.apply(snapshot(), repositoryURL: url)
		try await waitUntil { await content.count == 2 }
		let data = Data("new preview".utf8)
		await content.resume(1, with: .success(data))
		try await waitUntil {
			model.filePreview == .text(content: "new preview", byteCount: data.count)
		}
		await content.resume(0, with: .failure(GitRepositoryError.commandFailed("Old read failed")))
		try await Task.sleep(for: .milliseconds(50))
		#expect(model.filePreview == .text(content: "new preview", byteCount: data.count))
	}

	@Test
	func repeatedSelectionUpdatesImmediatelyAndLoadsOnlyTheSettledFile() async throws {
		let content = Content()
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: content))
		defer { model.onDisappear() }
		let files = (0..<1_000).map { file("File\($0).swift") }
		model.apply(snapshot(files), repositoryURL: URL(fileURLWithPath: "/repo"))
		let itemIDs = model.visibleTreeItems.map(\.id)

		for file in files.suffix(30) {
			model.didSelectTreeNode(id: file.id)
			#expect(model.selectedTreeNodeID == file.id)
			#expect(model.selectedTreeItem?.node == file)
			await Task.yield()
		}

		let last = try #require(files.last)
		try await waitUntil { await content.count > 0 }
		let data = Data("settled".utf8)
		await content.resume(0, with: .success(data))
		try await waitUntil {
			model.filePreview == .text(content: "settled", byteCount: data.count)
		}
		#expect(await content.paths == [last.path])
		#expect(model.visibleTreeItems.map(\.id) == itemIDs)
		#expect(model.fileCount == files.count)
	}

	@Test
	func collapsingAParentClearsSelectionAndIgnoresAnInFlightPreview() async throws {
		let content = Content()
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: content))
		defer { model.onDisappear() }
		let child = file("Sources/Value.swift")
		let directory = RepositoryTreeNode(name: "Sources", path: "Sources", children: [child])
		model.apply(snapshot([directory]), repositoryURL: URL(fileURLWithPath: "/repo"))
		model.setTreeNode(directory.id, isExpanded: true)
		model.didSelectTreeNode(id: child.id)
		try await waitUntil { await content.count == 1 }

		model.setTreeNode(directory.id, isExpanded: false)
		model.didSelectTreeNode(id: child.id)
		#expect(model.visibleTreeItems.map(\.id) == [directory.id])
		#expect(model.selectedTreeNodeID == nil)
		#expect(model.selectedTreeItem == nil)
		#expect(model.filePreview == .none)
		await content.resume(0, with: .success(Data("hidden".utf8)))

		model.setTreeNode(directory.id, isExpanded: true)
		model.didSelectTreeNode(id: child.id)
		try await waitUntil { await content.count == 2 }
		#expect(model.filePreview == .loading)
		let data = Data("visible".utf8)
		await content.resume(1, with: .success(data))
		try await waitUntil {
			model.filePreview == .text(content: "visible", byteCount: data.count)
		}
		#expect(model.visibleTreeItems.map(\.id) == [directory.id, child.id])
	}

	private func file(_ path: String) -> RepositoryTreeNode {
		.init(name: URL(fileURLWithPath: path).lastPathComponent, path: path, children: [])
	}

	private func snapshot(
		_ nodes: [RepositoryTreeNode] = [.init(name: "Value.swift", path: "Value.swift", children: [])]
	) -> RepositorySnapshot {
		.init(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal,
			tags: [], stashes: [],
			fileTree: nodes)
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(2))
		while await !condition() {
			guard ContinuousClock.now < deadline else {
				Issue.record("Timed out waiting for file preview")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
