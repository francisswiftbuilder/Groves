import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryTree

@MainActor
struct RepositoryTreeViewModelTests {
	private actor Content: RepositoryContentUseCase {
		private(set) var count = 0
		private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

		func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot { fatalError() }
		func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
			let id = count
			count += 1
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
	}

	@Test
	func cancelledPreviewFailureCannotReplaceANewerPreviewOfTheSameFile() async throws {
		let content = Content()
		let model = RepositoryTreeViewModel(dependencies: .init(contentUseCase: content))
		defer { model.onDisappear() }
		let url = URL(fileURLWithPath: "/repo")
		model.apply(snapshot(), repositoryURL: url)
		await model.didSelectTreeNode(id: "Value.swift")
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

	private func snapshot() -> RepositorySnapshot {
		.init(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal,
			tags: [], stashes: [],
			fileTree: [.init(name: "Value.swift", path: "Value.swift", children: [])])
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
