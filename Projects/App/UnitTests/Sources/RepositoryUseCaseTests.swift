import DomainGit
import DomainGitInterface
import Foundation
import Testing

@MainActor
struct RepositoryUseCaseTests {
	@Test
	func testOpeningRepositoryResolvesRootAndPersistsSelection() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let store = SavedRepositoryStoreSpy(repositories: [])
		let useCase = DefaultRepositoryTabsUseCase(
			repository: GitRepositoryStub(recorder: recorder),
			store: store
		)

		let savedRepository = try await useCase.openRepository(at: repositoryURL)
		let events = await recorder.recordedEvents()

		#expect(savedRepository.url == repositoryURL)
		#expect(store.selectedRepositoryID == savedRepository.id)
		#expect(events == [.repositoryRoot(repositoryURL)])
	}

	@Test
	func testStageRunsMutationBeforeReturningFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let change = WorkingTreeChange(
			path: "Sources/GalleryView.swift",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let stub = GitRepositoryStub(recorder: recorder, changes: [change])
		let useCase = DefaultRepositoryChangesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.stage([change], at: repositoryURL)
		let events = await recorder.recordedEvents()

		#expect(snapshot.changes == [change])
		#expect(events == [.stage(path: change.path)])
	}

	@Test
	func testPushWithoutUpstreamUsesSelectedRemoteAndReturnsSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
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
		let stub = GitRepositoryStub(
			recorder: recorder,
			branches: [branch],
			remotes: remotes
		)
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.push(
			currentBranch: branch,
			remotes: remotes,
			operationState: .normal,
			selectedRemoteName: "upstream",
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.branches == [branch])
		#expect(events == [.push(.setUpstream(remoteName: "upstream", branchName: branch.name))])
	}

	@Test
	func testForcePushUsesSelectedRemoteAndReturnsSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let branch = GitBranch(
			name: "feature/force-push",
			shortHash: "1234567",
			upstream: nil,
			isCurrent: true
		)
		let remotes = [
			GitRemote(name: "origin", fetchURL: nil, pushURL: nil),
			GitRemote(name: "upstream", fetchURL: nil, pushURL: nil),
		]
		let stub = GitRepositoryStub(
			recorder: recorder,
			branches: [branch],
			remotes: remotes
		)
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.forcePush(
			currentBranch: branch,
			remotes: remotes,
			operationState: .normal,
			selectedRemoteName: "origin",
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.branches == [branch])
		#expect(events == [.forcePush(.setUpstream(remoteName: "origin", branchName: branch.name))])
	}

	@Test
	func testPushTagsUsesExplicitRemoteAndReturnsSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let tag = GitTag(
			name: "release/1.0.0",
			shortHash: "1234567",
			targetHash: "1234567890abcdef",
			date: nil,
			subject: "Release 1.0.0"
		)
		let stub = GitRepositoryStub(recorder: recorder, tags: [tag])
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.pushTags(
			remote: "origin",
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.tags == [tag])
		#expect(events == [.pushTags(remoteName: "origin")])
	}

	@Test
	func testMergeBranchRunsMutationBeforeReturningFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
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
		let stub = GitRepositoryStub(
			recorder: recorder,
			branches: [currentBranch, mergeBranch]
		)
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.mergeBranch(
			named: mergeBranch.name,
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.branches == [currentBranch, mergeBranch])
		#expect(events == [.merge(branchName: mergeBranch.name)])
	}

	@Test
	func testCreateTagUsesExplicitCommitBeforeReturningFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let commit = GitCommit(
			hash: "1234567890abcdef",
			shortHash: "1234567",
			parentHashes: [],
			author: "Groves Tests",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: "Tagged commit",
			body: ""
		)
		let stub = GitRepositoryStub(recorder: recorder, commits: [commit])
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.createTag(
			named: "release/1.0.0",
			message: "Release 1.0.0",
			commitHash: commit.hash,
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.commits == [commit])
		#expect(
			events == [
				.createTag(
					name: "release/1.0.0",
					message: "Release 1.0.0",
					commitHash: commit.hash
				)
			])
	}

	@Test
	func testDeleteTagReturnsFreshSnapshot() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/Groves", isDirectory: true)
		let recorder = GitRepositoryRecorder()
		let branch = GitBranch(
			name: "main",
			shortHash: "1234567",
			upstream: nil,
			isCurrent: true
		)
		let stub = GitRepositoryStub(recorder: recorder, branches: [branch])
		let useCase = DefaultRepositoryReferencesUseCase(
			repository: stub,
			content: DefaultRepositoryContentUseCase(repository: stub)
		)

		let snapshot = try await useCase.deleteTag(
			named: "release/1.0.0",
			at: repositoryURL
		)
		let events = await recorder.recordedEvents()

		#expect(snapshot.branches == [branch])
		#expect(events == [.deleteTag(name: "release/1.0.0")])
	}
}
