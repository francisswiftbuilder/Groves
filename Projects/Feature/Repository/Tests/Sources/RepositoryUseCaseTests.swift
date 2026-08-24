import DomainGit
import DomainGitInterface
import Foundation
import XCTest

@MainActor
final class RepositoryUseCaseTests: XCTestCase {
	func testOpeningRepositoryResolvesRootAndPersistsSelection() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Trees", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let store = SavedRepositoryStoreSpy(repositories: [])
		let useCase = RepositoryUseCaseFactory.makeTabsUseCase(
			repository: GitRepositoryStub(recorder: recorder),
			savedRepositoryStore: store
		)

		let savedRepository = try await useCase.openRepository(at: repositoryURL)
		let events = await recorder.recordedEvents()

		XCTAssertEqual(savedRepository.url, repositoryURL)
		XCTAssertEqual(store.selectedRepositoryID, savedRepository.id)
		XCTAssertEqual(events, [.repositoryRoot(repositoryURL)])
	}

	func testStageRunsMutationBeforeReturningFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Trees", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let change = WorkingTreeChange(
			path: "Sources/GalleryView.swift",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let useCase = RepositoryUseCaseFactory.makeChangesUseCase(
			repository: GitRepositoryStub(recorder: recorder, changes: [change])
		)

		let snapshot = try await useCase.stage([change], at: repositoryURL)
		let events = await recorder.recordedEvents()

		XCTAssertEqual(snapshot.changes, [change])
		XCTAssertEqual(events, [.stage(path: change.path)])
	}

	func testPushWithoutUpstreamUsesSelectedRemoteAndReturnsSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Trees", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let branch = GitBranch(
			name: "feature/use-case",
			shortHash: "1234567",
			upstream: nil,
			isCurrent: true
		)
		let remotes = [
			GitRemote(name: "origin", fetchURL: nil, pushURL: nil),
			GitRemote(name: "upstream", fetchURL: nil, pushURL: nil),
		]
		let useCase = RepositoryUseCaseFactory.makeReferencesUseCase(
			repository: GitRepositoryStub(
				recorder: recorder,
				branches: [branch],
				remotes: remotes
			)
		)

		let snapshot = try await useCase.push(
			currentBranch: branch,
			remotes: remotes,
			operationState: .normal,
			selectedRemoteName: "upstream",
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		XCTAssertEqual(snapshot.branches, [branch])
		XCTAssertEqual(
			events,
			[.push(.setUpstream(remoteName: "upstream", branchName: branch.name))]
		)
	}

	func testMergeBranchRunsMutationBeforeReturningFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Trees", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let currentBranch = GitBranch(
			name: "main",
			shortHash: "1234567",
			upstream: nil,
			isCurrent: true
		)
		let mergeBranch = GitBranch(
			name: "feature/merge",
			shortHash: "7654321",
			upstream: nil,
			isCurrent: false
		)
		let useCase = RepositoryUseCaseFactory.makeReferencesUseCase(
			repository: GitRepositoryStub(
				recorder: recorder,
				branches: [currentBranch, mergeBranch]
			)
		)

		let snapshot = try await useCase.mergeBranch(
			named: mergeBranch.name,
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		XCTAssertEqual(snapshot.branches, [currentBranch, mergeBranch])
		XCTAssertEqual(events, [.merge(branchName: mergeBranch.name)])
	}
}
