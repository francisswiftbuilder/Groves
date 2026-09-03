import DomainGitInterface
import Foundation
import XCTest

@testable import CoreRepositoryDiff
@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryHistory
@testable import FeatureRepositoryOperations
@testable import FeatureRepositoryTree
@testable import Groves

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
	func testRefreshKeepsLoadedWorkspaceContentVisible() async throws {
		let workspace = makeRepositoryWorkspace()
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { !workspace.viewModel.isLoading }

		workspace.viewModel.didRequestRefresh()

		XCTAssertTrue(workspace.viewModel.isLoading)
		XCTAssertFalse(workspace.viewModel.isLoadingContent)
		try await waitUntil { !workspace.viewModel.isLoading }
	}

	func testRepositoryMonitorDoesNotRetainWorkspaceViewModel() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory.appending(
			path: "GrovesMonitorLifetime-\(UUID().uuidString)",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer { try? FileManager.default.removeItem(at: repositoryURL) }

		var workspace: RepositoryWorkspace? = makeRepositoryWorkspace()
		workspace?.viewModel.didChooseRepository(repositoryURL)
		try await waitUntil { workspace?.viewModel.repositoryURL == repositoryURL }
		workspace?.viewModel.onAppear(isSceneActive: true)
		weak var weakViewModel = workspace?.viewModel

		workspace = nil

		try await waitUntil { weakViewModel == nil }
	}

	func testResumingRepositoryMonitoringRefreshesMissedChanges() async throws {
		let contentGate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(contentGate: contentGate)
		)
		let repositoryURL = URL(fileURLWithPath: "/tmp/GrovesMonitorResume")
		workspace.viewModel.didChooseRepository(repositoryURL)
		try await waitUntilCallCount(
			1,
			of: GitDiffGateLabel.workingTreeChanges,
			in: contentGate
		)
		try await waitUntil { !workspace.viewModel.isLoading }

		workspace.viewModel.onAppear(isSceneActive: true)
		workspace.viewModel.didChangeSceneActivation(false)
		workspace.viewModel.didChangeSceneActivation(true)

		try await waitUntilCallCount(
			2,
			of: GitDiffGateLabel.workingTreeChanges,
			in: contentGate
		)
	}

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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }

		workspace.changesViewModel.selectedChangeIDs = [.staged(change.id)]
		workspace.changesViewModel.didChangeSelectedChanges()
		try await waitUntil { workspace.changesDiffViewModel.diff == "cached diff" }
		XCTAssertEqual(workspace.changesViewModel.selectedFileState, .modified)

		workspace.changesViewModel.selectedChangeIDs = [.unstaged(change.id)]
		workspace.changesViewModel.didChangeSelectedChanges()
		try await waitUntil { workspace.changesDiffViewModel.diff == "working tree diff" }
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
		try await waitUntil { trackedWorkspace.referencesViewModel.currentBranch == trackedBranch }
		XCTAssertEqual(trackedWorkspace.syncViewModel.pushAction, .upstream)

		let singleRemoteWorkspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(branches: [untrackedBranch], remotes: [origin])
		)
		singleRemoteWorkspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Single"))
		try await waitUntil {
			singleRemoteWorkspace.referencesViewModel.currentBranch == untrackedBranch
		}
		XCTAssertEqual(
			singleRemoteWorkspace.syncViewModel.pushAction,
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
			multipleRemoteWorkspace.referencesViewModel.currentBranch == untrackedBranch
		}
		XCTAssertEqual(
			multipleRemoteWorkspace.syncViewModel.pushAction,
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.referencesViewModel.currentBranch == branch }
		workspace.syncViewModel.didPresentForcePushConfirmation(remoteName: "upstream")

		guard case .forcePush(let remoteName) = workspace.syncViewModel.pendingConfirmation
		else {
			return XCTFail("Expected a force-push confirmation")
		}
		XCTAssertEqual(remoteName, "upstream")
		XCTAssertEqual(
			workspace.syncViewModel.forcePushConfirmationTitle, "Force Push feature/force-push?")

		workspace.syncViewModel.didConfirmPendingConfirmation()

		try await waitUntilRecorded(
			.forcePush(.setUpstream(remoteName: "upstream", branchName: branch.name)),
			by: recorder
		)
		XCTAssertNil(workspace.syncViewModel.pendingConfirmation)
	}

	func testPushTagsUsesSelectedRemote() async throws {
		let recorder = GitRepositoryRecorder()
		let origin = GitRemote(name: "origin", fetchURL: nil, pushURL: nil)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(recorder: recorder, remotes: [origin])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.remotesViewModel.remotes == [origin] }
		workspace.syncViewModel.didRequestPushTags(remoteName: origin.name)

		try await waitUntilRecorded(.pushTags(remoteName: origin.name), by: recorder)
	}

	func testRepositoryOperationStateIsLoadedIntoWorkspace() async throws {
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(operationState: .rebaseInProgress)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Rebase"))
		try await waitUntil { workspace.operationViewModel.operationState == .rebaseInProgress }

		XCTAssertEqual(workspace.referencesViewModel.currentBranchStatus, "Rebase in Progress")
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
		try await waitUntil { workspace.conflictViewModel.content != nil }

		XCTAssertEqual(workspace.changesViewModel.filteredConflicts, [conflict])
		XCTAssertTrue(workspace.changesViewModel.filteredStagedChanges.isEmpty)
		XCTAssertTrue(workspace.changesViewModel.filteredUnstagedChanges.isEmpty)
		XCTAssertEqual(workspace.changesViewModel.selectedChangeIDs, [.conflict(conflict.path)])

		await workspace.changesViewModel.didSelectChanges([])

		XCTAssertNil(workspace.conflictViewModel.content)
	}

	func testExternalEditorUsesConfiguredApplicationAndIgnoresDeletedConflict() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesExternalEditor-\(UUID().uuidString)", directoryHint: .isDirectory)
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

		workspace.conflictViewModel.didOpenInEditor(conflict)

		XCTAssertEqual(opener.openedFileURL, fileURL)
		XCTAssertEqual(opener.applicationBundleIdentifier, "com.example.Editor")
		try FileManager.default.removeItem(at: fileURL)
		workspace.conflictViewModel.didOpenInEditor(conflict)
		XCTAssertEqual(opener.invocationCount, 1)
	}

	func testUnavailableExternalEditorShowsSettingsRecovery() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesMissingEditor-\(UUID().uuidString)", directoryHint: .isDirectory)
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

		workspace.conflictViewModel.didOpenInEditor(conflict)

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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.referencesViewModel.currentBranch == currentBranch }
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
			author: "Groves Tests",
			date: Date(timeIntervalSince1970: 1),
			references: [],
			subject: "Selected commit",
			body: ""
		)
		let contextCommit = GitCommit(
			hash: "context-commit-hash",
			shortHash: "context",
			parentHashes: [],
			author: "Groves Tests",
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == 2 }
		workspace.historyViewModel.selectedCommitID = selectedCommit.id
		workspace.referencesViewModel.didPresentNewTag(for: contextCommit)
		workspace.referencesViewModel.newTagName = "context-tag"
		workspace.referencesViewModel.newTagMessage = "Context tag message"
		workspace.referencesViewModel.didRequestCreateTag()

		try await waitUntilRecorded(
			.createTag(
				name: "context-tag",
				message: "Context tag message",
				commitHash: contextCommit.hash
			),
			by: recorder
		)
		try await waitUntil { workspace.referencesViewModel.pendingTagCommit == nil }

		XCTAssertTrue(workspace.referencesViewModel.newTagName.isEmpty)
		XCTAssertTrue(workspace.referencesViewModel.newTagMessage.isEmpty)
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.referencesViewModel.tags == [tag] }
		workspace.referencesViewModel.didPresentTagDeletion(tag)

		guard case .deleteTag(let pendingTag) = workspace.referencesViewModel.pendingConfirmation
		else {
			return XCTFail("Expected a tag-deletion confirmation")
		}
		XCTAssertEqual(pendingTag, tag)
		XCTAssertEqual(
			workspace.referencesViewModel.pendingConfirmation?.title,
			"Delete “release/1.0.0”"
		)

		workspace.referencesViewModel.didConfirmPendingConfirmation()

		try await waitUntilRecorded(.deleteTag(name: tag.name), by: recorder)
		try await waitUntil { workspace.referencesViewModel.pendingConfirmation == nil }
	}

	func testOpeningBranchFocusesLatestCommitInHistory() async throws {
		let commits = (0...10).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < 10 ? ["commit-\(index + 1)"] : [],
				author: "Groves Tests",
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == commits.count }

		workspace.historyViewModel.didOpenBranch(branch)
		try await waitUntil { workspace.historyViewModel.selectedCommitID == "commit-7" }

		XCTAssertEqual(workspace.viewModel.selectedSection, .history)
		XCTAssertEqual(workspace.referencesViewModel.selectedBranchID, branch.id)
		XCTAssertEqual(workspace.historyViewModel.historyFocusRequest?.commitID, "commit-7")
	}

	func testOpeningRemoteBranchFocusesLatestCommitInHistory() async throws {
		let commit = GitCommit(
			hash: "remote-commit",
			shortHash: "remote",
			parentHashes: [],
			author: "Groves Tests",
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
			fetchURL: "https://example.com/Groves.git",
			pushURL: "https://example.com/Groves.git",
			branches: [branch]
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: [commit], remotes: [remote])
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.historyViewModel.commitGraphItems.count == 1 }

		workspace.historyViewModel.didOpenRemoteBranch(branch)

		XCTAssertEqual(workspace.viewModel.selectedSection, .history)
		XCTAssertEqual(workspace.remotesViewModel.selectedRemoteID, remote.id)
		XCTAssertEqual(workspace.historyViewModel.historyFocusRequest?.commitID, commit.id)
	}

	func testOpeningTagFocusesDistantCommitInCompleteHistory() async throws {
		let lastIndex = 600
		let commits = (0...lastIndex).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < lastIndex ? ["commit-\(index + 1)"] : [],
				author: "Groves Tests",
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesViewModel.changes.count == 2 }
		workspace.changesViewModel.filterText = "gallery"

		XCTAssertEqual(workspace.changesViewModel.filteredStagedChanges, [swiftChange])
		XCTAssertEqual(workspace.changesViewModel.filteredUnstagedChanges, [swiftChange])

		workspace.changesViewModel.didPresentDiscardConfirmation(
			for: [swiftChange, markdownChange]
		)

		guard case .discard(let pendingChanges) = workspace.changesViewModel.pendingConfirmation
		else {
			return XCTFail("Expected a discard confirmation")
		}
		XCTAssertEqual(pendingChanges, [swiftChange, markdownChange])
		XCTAssertEqual(
			workspace.changesViewModel.pendingConfirmation?.title,
			"Discard Changes to 2 Files?"
		)

		workspace.changesViewModel.didDismissPendingConfirmation()

		XCTAssertNil(workspace.changesViewModel.pendingConfirmation)
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
		workspace.referencesViewModel.didPresentNewBranch()
		workspace.referencesViewModel.newBranchName = "feature/view-model-state"

		XCTAssertFalse(workspace.viewModel.expandedSidebarGroups.contains(branchesGroup))
		XCTAssertTrue(workspace.treeViewModel.expandedTreeNodeIDs.contains("Sources"))
		XCTAssertTrue(workspace.referencesViewModel.isPresentingNewBranch)
		XCTAssertEqual(workspace.referencesViewModel.newBranchName, "feature/view-model-state")

		workspace.referencesViewModel.didDismissNewBranch()

		XCTAssertFalse(workspace.referencesViewModel.isPresentingNewBranch)
		XCTAssertTrue(workspace.referencesViewModel.newBranchName.isEmpty)
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
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
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }
		workspace.changesViewModel.selectedChangeIDs = [.unstaged(change.id)]

		XCTAssertEqual(workspace.changesDiffViewModel.selectedDiffLineAction, .stage)
		XCTAssertEqual(workspace.changesDiffViewModel.selectedDiffHunkActions, [.stage, .discard])
		XCTAssertEqual(workspace.changesViewModel.selectedStageableChanges, [change])

		workspace.diffPreferences.options.ignoresWhitespace = true

		XCTAssertNil(workspace.changesDiffViewModel.selectedDiffLineAction)
		XCTAssertTrue(workspace.changesDiffViewModel.selectedDiffHunkActions.isEmpty)
		XCTAssertEqual(workspace.changesViewModel.selectedStageableChanges, [change])
	}

	func testPartialDiffMutationReloadsUnchangedSelection() async throws {
		let recorder = GitRepositoryRecorder()
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				recorder: recorder,
				changes: [change],
				unstagedDiff: "diff"
			)
		)
		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesDiffViewModel.diff == "diff" }

		workspace.changesDiffViewModel.didRequestApplyDiffLine(
			GitDiffLineSelection(oldLineNumber: 1, newLineNumber: 1),
			action: .stage
		)

		try await waitUntilRecorded(.applyDiffLine(.stage), by: recorder)
		try await waitUntilRecordedCount(.loadDiff(.unstaged), count: 2, by: recorder)
		XCTAssertEqual(workspace.changesViewModel.selectedChangeIDs, [.unstaged(change.id)])
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
			author: "Groves",
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

		workspace.referencesViewModel.didPresentNewBranch(from: commit)
		workspace.referencesViewModel.newBranchName = "release/historical"
		workspace.referencesViewModel.didRequestCreateBranch()
		try await waitUntilRecorded(
			.createBranch(name: "release/historical", commitHash: commit.hash),
			by: recorder
		)

		try await waitUntil { !workspace.viewModel.isLoading }
		workspace.referencesViewModel.didPresentCheckoutCommit(commit)
		workspace.referencesViewModel.didConfirmPendingConfirmation()
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
			author: "Groves",
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
		workspace.commitViewModel.subject = "Blocked commit"

		XCTAssertFalse(workspace.commitViewModel.canCommit)
		XCTAssertFalse(workspace.commitViewModel.canAmendCommit)
		XCTAssertEqual(workspace.syncViewModel.pushAction, .unavailable)
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

	private func waitUntilRecordedCount(
		_ event: GitRepositoryRecorderEvent,
		count: Int,
		by recorder: GitRepositoryRecorder,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await recorder.recordedEvents().filter({ $0 == event }).count < count {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for repository event count")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func waitUntilCallCount(
		_ count: Int,
		of label: String,
		in gate: GitDiffGate,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.callCount(of: label) < count {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for call count")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
