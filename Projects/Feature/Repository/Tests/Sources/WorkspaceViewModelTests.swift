import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
	func testStagedAndUnstagedSelectionsUseIndependentDiffSources() async throws {
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				stagedDiff: "cached diff",
				unstagedDiff: "working tree diff"
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }

		workspace.changesViewModel.selectedChangeIDs = [.staged(change.id)]
		workspace.changesViewModel.didChangeSelectedChanges()
		try await waitUntil { workspace.changesViewModel.diff == "cached diff" }
		XCTAssertEqual(workspace.changesViewModel.selectedFileState, .modified)

		workspace.changesViewModel.selectedChangeIDs = [.unstaged(change.id)]
		workspace.changesViewModel.didChangeSelectedChanges()
		try await waitUntil { workspace.changesViewModel.diff == "working tree diff" }
		XCTAssertEqual(workspace.changesViewModel.selectedFileState, .modified)
	}

	func testPushActionUsesUpstreamOrModelsRemoteChoice() async throws {
		let trackedBranch = GitBranch(
			name: "main",
			shortHash: "1234567",
			upstream: "origin/main",
			isCurrent: true
		)
		let untrackedBranch = GitBranch(
			name: "feature/push",
			shortHash: "7654321",
			upstream: nil,
			isCurrent: true
		)
		let origin = GitRemote(name: "origin", fetchURL: nil, pushURL: nil)
		let upstream = GitRemote(name: "upstream", fetchURL: nil, pushURL: nil)

		let trackedWorkspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(branches: [trackedBranch], remotes: [origin])
		)
		trackedWorkspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Tracked"))
		try await waitUntil { trackedWorkspace.operationViewModel.currentBranch == trackedBranch }
		XCTAssertEqual(trackedWorkspace.operationViewModel.pushAction, .upstream)

		let singleRemoteWorkspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(branches: [untrackedBranch], remotes: [origin])
		)
		singleRemoteWorkspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Single"))
		try await waitUntil {
			singleRemoteWorkspace.operationViewModel.currentBranch == untrackedBranch
		}
		XCTAssertEqual(
			singleRemoteWorkspace.operationViewModel.pushAction,
			.setUpstream(remoteName: "origin", branchName: "feature/push")
		)

		let multipleRemoteWorkspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				branches: [untrackedBranch],
				remotes: [origin, upstream]
			)
		)
		multipleRemoteWorkspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Multiple"))
		try await waitUntil {
			multipleRemoteWorkspace.operationViewModel.currentBranch == untrackedBranch
		}
		XCTAssertEqual(
			multipleRemoteWorkspace.operationViewModel.pushAction,
			.chooseRemote(
				remoteNames: ["origin", "upstream"],
				branchName: "feature/push"
			)
		)
	}

	func testForcePushRequiresConfirmationAndUsesCapturedRemote() async throws {
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
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				recorder: recorder,
				branches: [branch],
				remotes: remotes
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.operationViewModel.currentBranch == branch }
		workspace.operationViewModel.didPresentForcePushConfirmation(remoteName: "upstream")

		XCTAssertTrue(workspace.viewModel.isPresentingForcePushConfirmation)
		XCTAssertEqual(
			workspace.operationViewModel.forcePushConfirmationTitle, "Force Push feature/force-push?")

		workspace.viewModel.didConfirmForcePush()

		try await waitUntilRecorded(
			.forcePush(.setUpstream(remoteName: "upstream", branchName: branch.name)),
			by: recorder
		)
		XCTAssertFalse(workspace.viewModel.isPresentingForcePushConfirmation)
	}

	func testPushTagsUsesSelectedRemote() async throws {
		let recorder = GitRepositoryRecorder()
		let origin = GitRemote(name: "origin", fetchURL: nil, pushURL: nil)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(recorder: recorder, remotes: [origin])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.operationViewModel.remotes == [origin] }
		workspace.operationViewModel.didRequestPushTags(remoteName: origin.name)

		try await waitUntilRecorded(.pushTags(remoteName: origin.name), by: recorder)
	}

	func testRepositoryOperationStateIsLoadedIntoWorkspace() async throws {
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(operationState: .rebaseInProgress)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Rebase"))
		try await waitUntil { workspace.operationViewModel.operationState == .rebaseInProgress }

		XCTAssertEqual(workspace.operationViewModel.currentBranchStatus, "Rebase in Progress")
	}

	func testConflictsAreExcludedFromStagedAndUnstagedSections() async throws {
		let change = WorkingTreeChange(
			path: "Sources/Conflict.swift",
			previousPath: nil,
			indexState: .unmerged,
			workingTreeState: .unmerged
		)
		let conflict = GitConflict(
			path: change.path,
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				operationState: RepositoryOperationState(
					head: .attached,
					operation: RepositoryOperation(kind: .merge),
					conflicts: [conflict]
				)
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Conflict"))
		try await waitUntil { workspace.changesViewModel.conflicts == [conflict] }

		XCTAssertEqual(workspace.changesViewModel.filteredConflicts, [conflict])
		XCTAssertTrue(workspace.changesViewModel.filteredStagedChanges.isEmpty)
		XCTAssertTrue(workspace.changesViewModel.filteredUnstagedChanges.isEmpty)
		XCTAssertEqual(workspace.changesViewModel.selectedChangeIDs, [.conflict(conflict.path)])
	}

	func testExternalEditorUsesConfiguredApplicationAndIgnoresDeletedConflict() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesExternalEditor-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			UserDefaults.standard.removeObject(forKey: "externalEditorBundleIdentifier")
		}
		let conflict = GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		let fileURL = repositoryURL.appending(path: conflict.path)
		try Data("conflict".utf8).write(to: fileURL)
		let opener = RepositoryExternalEditorOpenerSpy()
		let workspace = makeRepositoryWorkspace(externalEditorOpener: opener)
		workspace.viewModel.didChooseRepository(repositoryURL)
		try await waitUntil { workspace.viewModel.repositoryURL == repositoryURL }
		UserDefaults.standard.set("com.example.Editor", forKey: "externalEditorBundleIdentifier")

		workspace.changesViewModel.didOpenConflictInEditor(conflict)

		XCTAssertEqual(opener.openedFileURL, fileURL)
		XCTAssertEqual(opener.applicationBundleIdentifier, "com.example.Editor")
		try FileManager.default.removeItem(at: fileURL)
		workspace.changesViewModel.didOpenConflictInEditor(conflict)
		XCTAssertEqual(opener.invocationCount, 1)
	}

	func testUnavailableExternalEditorShowsSettingsRecovery() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesMissingEditor-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let conflict = GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		try Data("conflict".utf8).write(to: repositoryURL.appending(path: conflict.path))
		let opener = RepositoryExternalEditorOpenerSpy()
		opener.error = CocoaError(.fileNoSuchFile)
		let workspace = makeRepositoryWorkspace(externalEditorOpener: opener)
		workspace.viewModel.didChooseRepository(repositoryURL)
		try await waitUntil { workspace.viewModel.repositoryURL == repositoryURL }

		workspace.changesViewModel.didOpenConflictInEditor(conflict)

		XCTAssertEqual(
			workspace.viewModel.alertMessage,
			"The selected editor is unavailable. Choose another app in Settings."
		)
	}

	func testMergeBranchUsesExplicitContextMenuBranch() async throws {
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
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				recorder: recorder,
				branches: [currentBranch, mergeBranch]
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.operationViewModel.currentBranch == currentBranch }
		XCTAssertTrue(workspace.operationViewModel.canMergeBranch(mergeBranch))
		XCTAssertFalse(workspace.operationViewModel.canMergeBranch(currentBranch))

		workspace.operationViewModel.didRequestMergeBranch(mergeBranch)
		try await waitUntilRecorded(
			.merge(branchName: mergeBranch.name),
			by: recorder
		)
	}

	func testCreateTagUsesExplicitContextMenuCommit() async throws {
		let recorder = GitRepositoryRecorder()
		let selectedCommit = GitCommit(
			hash: "selected-commit-hash",
			shortHash: "selected",
			parentHashes: [],
			author: "Trees Tests",
			date: Date(timeIntervalSince1970: 1),
			references: [],
			subject: "Selected commit",
			body: ""
		)
		let contextCommit = GitCommit(
			hash: "context-commit-hash",
			shortHash: "context",
			parentHashes: [],
			author: "Trees Tests",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: "Context commit",
			body: ""
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				recorder: recorder,
				commits: [selectedCommit, contextCommit]
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == 2 }
		workspace.historyViewModel.selectedCommitID = selectedCommit.id
		workspace.operationViewModel.didPresentNewTag(for: contextCommit)
		workspace.operationViewModel.newTagName = "context-tag"
		workspace.operationViewModel.newTagMessage = "Context tag message"
		workspace.operationViewModel.didRequestCreateTag()

		try await waitUntilRecorded(
			.createTag(
				name: "context-tag",
				message: "Context tag message",
				commitHash: contextCommit.hash
			),
			by: recorder
		)
		try await waitUntil { workspace.operationViewModel.pendingTagCommit == nil }

		XCTAssertTrue(workspace.operationViewModel.newTagName.isEmpty)
		XCTAssertTrue(workspace.operationViewModel.newTagMessage.isEmpty)
	}

	func testDeleteTagUsesExplicitContextMenuTag() async throws {
		let recorder = GitRepositoryRecorder()
		let tag = GitTag(
			name: "release/1.0.0",
			shortHash: "1234567",
			targetHash: "1234567890abcdef",
			date: nil,
			subject: "Release 1.0.0"
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(recorder: recorder, tags: [tag])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.operationViewModel.tags == [tag] }
		workspace.operationViewModel.didPresentTagDeletion(tag)

		XCTAssertEqual(workspace.viewModel.pendingTagDeletion, tag)
		XCTAssertEqual(workspace.viewModel.deleteTagConfirmationTitle, "Delete “release/1.0.0”?")

		workspace.viewModel.didConfirmTagDeletion(tag)

		try await waitUntilRecorded(.deleteTag(name: tag.name), by: recorder)
		try await waitUntil { workspace.viewModel.pendingTagDeletion == nil }
	}

	func testOpeningBranchFocusesLatestCommitInHistory() async throws {
		let commits = (0...10).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < 10 ? ["commit-\(index + 1)"] : [],
				author: "Trees Tests",
				date: Date(timeIntervalSince1970: TimeInterval(10 - index)),
				references: [],
				subject: "Commit \(index)",
				body: ""
			)
		}
		let branch = GitBranch(
			name: "feature/history-navigation",
			shortHash: "short-7",
			upstream: nil,
			isCurrent: false
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: commits)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == commits.count }

		workspace.historyViewModel.didOpenBranch(branch)
		try await waitUntil { workspace.historyViewModel.selectedCommitID == "commit-7" }

		XCTAssertEqual(workspace.viewModel.selectedSection, .history)
		XCTAssertEqual(workspace.operationViewModel.selectedBranchID, branch.id)
		XCTAssertEqual(workspace.historyViewModel.historyFocusRequest?.commitID, "commit-7")
	}

	func testOpeningRemoteBranchFocusesLatestCommitInHistory() async throws {
		let commit = GitCommit(
			hash: "remote-commit",
			shortHash: "remote",
			parentHashes: [],
			author: "Trees Tests",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: "Remote commit",
			body: ""
		)
		let branch = GitRemoteBranch(
			name: "main",
			fullName: "origin/main",
			remoteName: "origin",
			shortHash: commit.shortHash,
			hash: commit.hash
		)
		let remote = GitRemote(
			name: "origin",
			fetchURL: "https://example.com/Trees.git",
			pushURL: "https://example.com/Trees.git",
			branches: [branch]
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: [commit], remotes: [remote])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == 1 }

		workspace.historyViewModel.didOpenRemoteBranch(branch)

		XCTAssertEqual(workspace.viewModel.selectedSection, .history)
		XCTAssertEqual(workspace.operationViewModel.selectedRemoteID, remote.id)
		XCTAssertEqual(workspace.historyViewModel.historyFocusRequest?.commitID, commit.id)
	}

	func testOpeningTagFocusesDistantCommitInCompleteHistory() async throws {
		let lastIndex = 600
		let commits = (0...lastIndex).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < lastIndex ? ["commit-\(index + 1)"] : [],
				author: "Trees Tests",
				date: Date(timeIntervalSince1970: TimeInterval(lastIndex - index)),
				references: [],
				subject: "Commit \(index)",
				body: ""
			)
		}
		let tag = GitTag(
			name: "deep-tag",
			shortHash: "short-\(lastIndex)",
			targetHash: "commit-\(lastIndex)",
			date: nil,
			subject: "Commit \(lastIndex)"
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: commits, tags: [tag])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == commits.count }

		workspace.historyViewModel.didOpenTag(tag)
		try await waitUntil { workspace.historyViewModel.selectedCommitID == tag.targetHash }

		XCTAssertEqual(workspace.historyViewModel.commitGraphItems.count, commits.count)
		XCTAssertEqual(workspace.viewModel.selectedSection, .history)
		XCTAssertEqual(workspace.historyViewModel.historyFocusRequest?.commitID, tag.targetHash)
	}

	func testViewModelOwnsChangeFilteringAndDiscardPresentation() async throws {
		let swiftChange = WorkingTreeChange(
			path: "Sources/GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let markdownChange = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [swiftChange, markdownChange])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesViewModel.changes.count == 2 }
		workspace.changesViewModel.filterText = "gallery"

		XCTAssertEqual(workspace.changesViewModel.filteredStagedChanges, [swiftChange])
		XCTAssertEqual(workspace.changesViewModel.filteredUnstagedChanges, [swiftChange])

		workspace.changesViewModel.didPresentDiscardConfirmation(
			for: [swiftChange, markdownChange]
		)

		XCTAssertEqual(workspace.viewModel.pendingDiscardChanges, [swiftChange, markdownChange])
		XCTAssertEqual(workspace.viewModel.discardConfirmationTitle, "Discard Changes to 2 Files?")

		workspace.viewModel.didDismissDiscardConfirmation()

		XCTAssertNil(workspace.viewModel.pendingDiscardChanges)
	}

	func testViewModelOwnsSidebarTreeAndNewBranchPresentationState() async {
		let workspace = makeRepositoryWorkspace()
		let repositoryID = UUID()
		let branchesGroup = RepositorySidebarGroup(
			repositoryID: repositoryID,
			kind: .branches
		)

		workspace.viewModel.didPrepareSidebar(repositoryID: repositoryID)

		XCTAssertTrue(workspace.viewModel.expandedSidebarGroups.contains(branchesGroup))

		workspace.viewModel.setSidebarGroup(branchesGroup, isExpanded: false)
		workspace.treeViewModel.setTreeNode("Sources", isExpanded: true)
		workspace.operationViewModel.didPresentNewBranch()
		workspace.operationViewModel.newBranchName = "feature/view-model-state"

		XCTAssertFalse(workspace.viewModel.expandedSidebarGroups.contains(branchesGroup))
		XCTAssertTrue(workspace.treeViewModel.expandedTreeNodeIDs.contains("Sources"))
		XCTAssertTrue(workspace.operationViewModel.isPresentingNewBranch)
		XCTAssertEqual(workspace.operationViewModel.newBranchName, "feature/view-model-state")

		workspace.operationViewModel.didDismissNewBranch()

		XCTAssertFalse(workspace.operationViewModel.isPresentingNewBranch)
		XCTAssertTrue(workspace.operationViewModel.newBranchName.isEmpty)
	}

	func testSelectionEventsPublishAfterSwiftUIUpdateCycle() async throws {
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }
		await workspace.changesViewModel.didSelectChanges([.unstaged(change.id)])

		XCTAssertEqual(workspace.changesViewModel.selectedChangeIDs, [.unstaged(change.id)])
	}

	func testIgnoreAllWhitespaceDisablesPartialActionsOnly() async throws {
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change], unstagedDiff: "diff")
		)
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }
		workspace.changesViewModel.selectedChangeIDs = [.unstaged(change.id)]

		XCTAssertEqual(workspace.changesViewModel.selectedDiffLineAction, .stage)
		XCTAssertEqual(workspace.changesViewModel.selectedDiffHunkActions, [.stage, .discard])
		XCTAssertEqual(workspace.changesViewModel.selectedStageableChanges, [change])

		workspace.diffPreferences.options.ignoresWhitespace = true

		XCTAssertNil(workspace.changesViewModel.selectedDiffLineAction)
		XCTAssertTrue(workspace.changesViewModel.selectedDiffHunkActions.isEmpty)
		XCTAssertEqual(workspace.changesViewModel.selectedStageableChanges, [change])
	}

	func testHistorySearchFiltersMetadataAfterDebounce() async throws {
		let first = GitCommit(
			hash: "1111111111111111111111111111111111111111",
			shortHash: "1111111",
			parentHashes: [],
			author: "Mina",
			authorEmail: "mina@example.com",
			date: Date(),
			references: ["HEAD -> main"],
			subject: "Initial commit",
			body: "Bootstrap repository"
		)
		let second = GitCommit(
			hash: "2222222222222222222222222222222222222222",
			shortHash: "2222222",
			parentHashes: [first.hash],
			author: "Joon",
			authorEmail: "joon@example.com",
			date: Date(),
			references: ["tag: release/1.0"],
			subject: "Ship release",
			body: "Production ready"
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: [second, first])
		)
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/History"))
		try await waitUntil { workspace.historyViewModel.displayedCommitGraphItems.count == 2 }

		workspace.historyViewModel.didChangeSearchText("mina@example.com")
		try await waitUntil {
			workspace.historyViewModel.displayedCommitGraphItems.map(\.commit) == [first]
		}
		workspace.historyViewModel.didChangeSearchText("release/1.0")
		try await waitUntil {
			workspace.historyViewModel.displayedCommitGraphItems.map(\.commit) == [second]
		}
		workspace.historyViewModel.didChangeSearchText("production ready")
		try await waitUntil {
			workspace.historyViewModel.displayedCommitGraphItems.map(\.commit) == [second]
		}
		workspace.historyViewModel.didChangeSearchText("missing")
		try await waitUntil { workspace.historyViewModel.displayedCommitGraphItems.isEmpty }
	}

	func testCreateBranchFromCommitAndCheckoutCommitUseExplicitCommit() async throws {
		let recorder = GitRepositoryRecorder()
		let commit = GitCommit(
			hash: "1234567890abcdef1234567890abcdef12345678",
			shortHash: "1234567",
			parentHashes: [],
			author: "Trees",
			date: Date(),
			references: [],
			subject: "Historical commit",
			body: ""
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(recorder: recorder, commits: [commit])
		)
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/HistoryActions"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == 1 }

		workspace.operationViewModel.didPresentNewBranch(from: commit)
		workspace.operationViewModel.newBranchName = "release/historical"
		workspace.operationViewModel.didRequestCreateBranch()
		try await waitUntilRecorded(
			.createBranch(name: "release/historical", commitHash: commit.hash),
			by: recorder
		)

		try await waitUntil { !workspace.viewModel.isLoading }
		workspace.operationViewModel.didPresentCheckoutCommit(commit)
		workspace.viewModel.didConfirmPendingRepositoryConfirmation()
		try await waitUntilRecorded(.checkoutCommit(commit.hash), by: recorder)
	}

	func testDetachedHeadDisablesBranchDependentActions() async throws {
		let change = WorkingTreeChange(
			path: "staged.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)
		let commit = GitCommit(
			hash: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
			shortHash: "abcdefa",
			parentHashes: [],
			author: "Trees",
			date: Date(),
			references: ["HEAD"],
			subject: "Detached",
			body: ""
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				commits: [commit],
				operationState: .detachedHead
			)
		)
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Detached"))
		try await waitUntil { workspace.operationViewModel.operationState.isDetached }
		workspace.changesViewModel.commitSubject = "Blocked commit"

		XCTAssertFalse(workspace.changesViewModel.canCommit)
		XCTAssertFalse(workspace.changesViewModel.canAmendCommit)
		XCTAssertEqual(workspace.operationViewModel.pushAction, .unavailable)
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !condition() {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func waitUntilRecorded(
		_ event: GitRepositoryRecorderEvent,
		by recorder: GitRepositoryRecorder,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !(await recorder.recordedEvents().contains(event)) {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for repository event")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
