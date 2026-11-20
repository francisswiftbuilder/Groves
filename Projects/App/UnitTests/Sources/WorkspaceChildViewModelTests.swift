import AppKit
import CoreRepositoryDiff
import DomainGitInterface
import Foundation
import SwiftUI
import Testing

@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryHistory
@testable import FeatureRepositoryStashes
@testable import FeatureRepositoryTree
@testable import Pluminon

@MainActor
struct WorkspaceChildViewModelTests {
	@Test
	func testRepositoryWorkspaceOwnsChildViewModelLifetime() {
		var workspace: RepositoryWorkspace? = makeRepositoryWorkspace()
		let viewModel = workspace?.viewModel
		weak let changesViewModel = workspace?.changesViewModel
		weak let changesDiffViewModel = workspace?.changesDiffViewModel
		weak let commitViewModel = workspace?.commitViewModel
		weak let conflictViewModel = workspace?.conflictViewModel
		weak let historyViewModel = workspace?.historyViewModel
		weak let operationViewModel = workspace?.operationViewModel
		weak let referencesViewModel = workspace?.referencesViewModel
		weak let syncViewModel = workspace?.syncViewModel
		weak let remotesViewModel = workspace?.remotesViewModel
		weak let stashesViewModel = workspace?.stashesViewModel
		weak let treeViewModel = workspace?.treeViewModel
		weak let diffPreferences = workspace?.diffPreferences
		weak let focusedActionsViewModel = workspace?.focusedActionsViewModel

		workspace = nil

		#expect(viewModel != nil)
		#expect(changesViewModel == nil)
		#expect(changesDiffViewModel == nil)
		#expect(commitViewModel == nil)
		#expect(conflictViewModel == nil)
		#expect(historyViewModel == nil)
		#expect(operationViewModel == nil)
		#expect(referencesViewModel == nil)
		#expect(syncViewModel == nil)
		#expect(remotesViewModel == nil)
		#expect(stashesViewModel == nil)
		#expect(treeViewModel == nil)
		#expect(diffPreferences == nil)
		#expect(focusedActionsViewModel == nil)
	}

	@Test
	func testSnapshotIsDistributedAcrossChildViewModels() async throws {
		let workspace = makeRepositoryWorkspace()
		let preferences = workspace.diffPreferences
		let changesViewModel = workspace.changesViewModel
		let changesDiffViewModel = workspace.changesDiffViewModel
		let historyViewModel = workspace.historyViewModel
		let referencesViewModel = workspace.referencesViewModel
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)
		let commit = GitCommit(
			hash: "abcdef123456",
			shortHash: "abcdef1",
			parentHashes: [],
			author: "Pluminon",
			date: .distantPast,
			references: ["HEAD"],
			subject: "Initial",
			body: ""
		)
		let branch = GitBranch(
			name: "develop",
			shortHash: "abcdef1",
			upstream: nil,
			isCurrent: true
		)
		let snapshot = RepositorySnapshot(
			changes: [change],
			amendChanges: [],
			commits: [commit],
			branches: [branch],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)

		workspace.viewModel.didProduceSnapshot(snapshot)
		try await waitUntil { historyViewModel.commitGraphItems.isEmpty == false }

		#expect(changesViewModel.changes == [change])
		#expect(historyViewModel.commitGraphItems.map(\.commit) == [commit])
		#expect(referencesViewModel.branches == [branch])
		#expect(changesDiffViewModel.preferences === preferences)
	}

	@Test
	func testWorkspaceDisappearCancelsPendingDebouncedSearch() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = [
			GitCommit(
				hash: "111111111111",
				shortHash: "1111111",
				parentHashes: [],
				author: "Pluminon",
				date: .distantPast,
				references: ["HEAD"],
				subject: "First",
				body: ""
			),
			GitCommit(
				hash: "222222222222",
				shortHash: "2222222",
				parentHashes: [],
				author: "Pluminon",
				date: .distantPast,
				references: [],
				subject: "Second",
				body: ""
			),
		]
		let snapshot = RepositorySnapshot(
			changes: [],
			amendChanges: [],
			commits: commits,
			branches: [],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)

		workspace.viewModel.didProduceSnapshot(snapshot)
		try await waitUntil { historyViewModel.commitGraphItems.count == commits.count }

		historyViewModel.didChangeSearchText("missing")
		workspace.onDisappear()
		try await Task.sleep(for: .milliseconds(200))

		#expect(historyViewModel.displayedCommitGraphItems.count == commits.count)
	}

	@Test
	func testWorkspaceAppearResumesIncompleteHistoryLayout() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = (0..<1_000).reversed().map { index in
			GitCommit(
				hash: String(format: "%040d", index),
				shortHash: String(format: "%07d", index),
				parentHashes: index == 0 ? [] : [String(format: "%040d", index - 1)],
				author: "Pluminon",
				date: .distantPast,
				references: index == 999 ? ["HEAD"] : [],
				subject: "Commit \(index)",
				body: ""
			)
		}

		workspace.viewModel.didProduceSnapshot(
			RepositorySnapshot(
				changes: [],
				amendChanges: [],
				commits: commits,
				branches: [],
				remotes: [],
				operationState: .normal,
				tags: [],
				stashes: [],
				fileTree: []
			)
		)
		workspace.onDisappear()
		workspace.onAppear()

		try await waitUntil { historyViewModel.commitGraphItems.count == commits.count }

		#expect(historyViewModel.commitGraphItems.map(\.commit) == commits)
	}

	@Test
	func testStashesViewModelTracksWorkingTreeStateWithoutTheChangesViewModel() {
		let workspace = makeRepositoryWorkspace()
		let stashesViewModel = workspace.stashesViewModel
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)

		#expect(!(stashesViewModel.hasChanges))

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [change]))

		#expect(stashesViewModel.hasChanges)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: []))

		#expect(!(stashesViewModel.hasChanges))

		stashesViewModel.didChangeWorkingTreeState(hasChanges: true)

		#expect(stashesViewModel.hasChanges)

		stashesViewModel.reset()

		#expect(!(stashesViewModel.hasChanges))
	}

	@Test
	func testFocusedActionsFollowLifecycleAndSelectionState() async {
		let workspace = makeRepositoryWorkspace()
		let branch = GitBranch(
			name: "feature",
			shortHash: "abcdef1",
			upstream: nil,
			isCurrent: false
		)
		workspace.viewModel.didProduceSnapshot(
			RepositorySnapshot(
				changes: [],
				amendChanges: [],
				commits: [],
				branches: [branch],
				remotes: [],
				operationState: .normal,
				tags: [],
				stashes: [],
				fileTree: []
			)
		)
		workspace.referencesViewModel.selectedBranchID = branch.id
		workspace.onAppear()
		await Task.yield()

		#expect(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch != nil)

		workspace.onDisappear()
		workspace.referencesViewModel.selectedBranchID = nil
		await Task.yield()
		#expect(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch == nil)

		workspace.onAppear()
		#expect(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch == nil)
	}

	@Test(arguments: [0, 1, 2])
	func testFocusedSyncActionsFollowRemoteAndHeadState(remoteCount: Int) {
		let workspace = makeRepositoryWorkspace()
		defer { workspace.onDisappear() }
		let remotes = ["origin", "upstream"].prefix(remoteCount).map {
			GitRemote(name: $0, fetchURL: "https://example.com/\($0).git", pushURL: nil)
		}
		let branches = [GitBranch(name: "main", shortHash: "abcdef0", upstream: nil, isCurrent: true)]
		func apply(branches: [GitBranch], state: RepositoryOperationState) {
			workspace.viewModel.didProduceSnapshot(
				.init(
					changes: [], amendChanges: [], commits: [], branches: branches, remotes: remotes,
					operationState: state, tags: [], stashes: [], fileTree: []))
		}

		apply(branches: branches, state: .normal)
		let actions = workspace.focusedActionsViewModel.focusedActions
		#expect(actions.newBranch != nil)
		#expect((actions.fetchAll != nil) == (remoteCount > 0))
		#expect(actions.pull == nil)
		#expect((actions.push != nil) == (remoteCount == 1))
		#expect((actions.pushToRemote != nil) == (remoteCount == 2))
		#expect(actions.pushRemoteNames == (remoteCount == 2 ? ["origin", "upstream"] : []))

		let trackedBranches = [
			GitBranch(
				name: "main", shortHash: "abcdef0", upstream: remoteCount > 0 ? "origin/main" : nil,
				isCurrent: true)
		]
		apply(branches: trackedBranches, state: .normal)
		#expect((workspace.focusedActionsViewModel.focusedActions.pull != nil) == (remoteCount > 0))

		apply(branches: [], state: .detachedHead)
		let detachedActions = workspace.focusedActionsViewModel.focusedActions
		#expect(detachedActions.newBranch != nil)
		#expect((detachedActions.fetchAll != nil) == (remoteCount > 0))
		#expect(detachedActions.pull == nil)
		#expect(detachedActions.push == nil)
		#expect(detachedActions.pushToRemote == nil)

		apply(branches: branches, state: .mergeInProgress)
		let mergingActions = workspace.focusedActionsViewModel.focusedActions
		#expect(mergingActions.newBranch == nil)
		#expect(mergingActions.pull == nil)
		#expect(mergingActions.push == nil)
		#expect((mergingActions.fetchAll != nil) == (remoteCount > 0))
	}

	@Test(arguments: [CGFloat(900), CGFloat(2_400)])
	func holdingHistoryArrowKeysKeepsNativeScrollingInOneDirection(width: CGFloat) async throws {
		let commit = GitCommit(
			hash: String(repeating: "a", count: 40), shortHash: "aaaaaaa",
			parentHashes: [String(repeating: "b", count: 40)], author: "Pluminon",
			authorEmail: "developer@example.com", date: .distantPast,
			committerEmail: "developer@example.com", references: ["origin/refactor/practice-test"],
			subject: "wip: 실전문제풀이 리팩터링 및 SwiftUICore 대응", body: "")
		let diff = (0..<112).map { index in
			let path =
				index.isMultiple(of: 3)
				? "File\(index).swift"
				: "Projects/Domain/PracticeTest/Interface/Sources/UseCase/PracticeTestAction\(index)UseCase.swift"
			let lineCount = index.isMultiple(of: 5) ? 643 : index % 87 + 1
			return """
				diff --git a/\(path) b/\(path)
				--- a/\(path)
				+++ b/\(path)
				@@ -0,0 +1,\(lineCount) @@
				""" + "\n" + (0..<lineCount).map { "+let value\($0) = \($0)" }.joined(separator: "\n")
		}.joined(separator: "\n")
		let workspace = makeRepositoryWorkspace()
		defer { workspace.onDisappear() }
		let model = workspace.historyViewModel
		model.apply(
			RepositorySnapshot(
				changes: [], amendChanges: [], commits: [commit], branches: [], remotes: [],
				operationState: .normal, tags: [], stashes: [], fileTree: []))
		try await waitUntil { model.commitGraphItems.count == 1 }
		model.selectedCommitFiles = CommitDiffFileParser.parse(diff)
		model.selectedCommitFileID = model.selectedCommitFiles.first?.id
		#expect(NSApplication.shared.isRunning)

		let controller = NSHostingController(
			rootView: HistoryView(
				diffSearchViewModel: RepositorySearchViewModel(), historyViewModel: model,
				diffPreferences: WorkspaceDiffPreferences(), repositoryName: "Pluminon",
				currentBranchStatus: "main", operationState: .normal, isOperationLoading: false,
				canCheckoutCommit: true, remoteNames: [],
				commitActions: RepositoryCommitActions(
					cherryPick: { _ in }, revert: { _ in }, createBranch: { _ in },
					checkoutCommit: { _ in }, createTag: { _ in }, reset: { _ in }),
				onDiffOptionsChanged: {}
			).frame(width: width, height: 1_000))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 1_000), styleMask: [.titled],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		window.makeKeyAndOrderFront(nil)
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		try await settleLayout(controller.view)
		let table = try #require(fileTable(in: controller.view))
		let scrollView = try #require(table.enclosingScrollView)
		#expect(window.makeFirstResponder(table))
		let firstFileRow = table.numberOfRows - model.selectedCommitFiles.count
		table.selectRowIndexes(IndexSet(integer: firstFileRow), byExtendingSelection: false)
		table.scrollRowToVisible(firstFileRow)
		try await settleLayout(controller.view)
		try #require(table.selectedRow == firstFileRow)
		let trace = ScrollTrace()
		let clip = scrollView.contentView
		let postsBoundsChangedNotifications = clip.postsBoundsChangedNotifications
		clip.postsBoundsChangedNotifications = true
		defer { clip.postsBoundsChangedNotifications = postsBoundsChangedNotifications }
		let observer = NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
		) { _ in
			MainActor.assumeIsolated { trace.offsets.append(clip.bounds.minY) }
		}
		defer { NotificationCenter.default.removeObserver(observer) }
		for direction in [1, -1] {
			trace.offsets = [clip.bounds.minY]
			for _ in 0..<160 {
				try pressArrow(direction, in: table, isARepeat: true)
				try await Task.sleep(for: .milliseconds(16))
			}
			try await settleLayout(controller.view, passes: 30)
			let expectedIndex = direction > 0 ? model.selectedCommitFiles.count - 1 : 0
			#expect(table.selectedRow == firstFileRow + expectedIndex)
			#expect(model.selectedCommitFileID == model.selectedCommitFiles[expectedIndex].id)
			try #require(trace.offsets.count > 2)
			let reversed = zip(trace.offsets, trace.offsets.dropFirst()).filter {
				($0.1 - $0.0) * CGFloat(direction) < -1
			}
			#expect(reversed.isEmpty, "direction \(direction), reversed scroll \(reversed)")
			let row = table.rect(ofRow: table.selectedRow)
			let viewport = fileViewport(
				in: table, headerHeight: table.rect(ofRow: firstFileRow - 1).height)
			#expect(row.minY >= viewport.minY - 1 && row.maxY <= viewport.maxY + 1)
		}
	}

	@Test(arguments: [CGFloat(900), CGFloat(2_400)])
	func holdingFilesArrowKeysKeepsNativeScrollingInOneDirection(width: CGFloat) async throws {
		let files = (0..<112).map { index -> RepositoryTreeNode in
			if index.isMultiple(of: 5) {
				let name = "Feature\(index)"
				let child = RepositoryTreeNode(
					name: "Content.swift", path: "\(name)/Content.swift", children: [])
				return RepositoryTreeNode(name: name, path: name, children: [child])
			}
			let name = "RepositoryContentAndPreviewProvider\(index).swift"
			return RepositoryTreeNode(name: name, path: name, children: [])
		}
		let workspace = makeRepositoryWorkspace()
		defer { workspace.onDisappear() }
		let model = workspace.treeViewModel
		let repositoryURL = URL(fileURLWithPath: "/repo")
		func snapshot(_ nodes: [RepositoryTreeNode]) -> RepositorySnapshot {
			RepositorySnapshot(
				changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
				operationState: .normal, tags: [], stashes: [], fileTree: nodes)
		}
		model.apply(snapshot(files), repositoryURL: repositoryURL)
		var refreshedFiles = files
		let directory = files[0]
		refreshedFiles[0] = RepositoryTreeNode(
			name: directory.name, path: directory.path,
			children: directory.children + [
				RepositoryTreeNode(
					name: "New.swift", path: "\(directory.path)/New.swift", children: [])
			])
		model.didSelectTreeNode(id: files[0].id)
		let controller = NSHostingController(
			rootView: RepositoryTreeView(viewModel: model).frame(width: width, height: 660))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 660), styleMask: [.titled],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		window.makeKeyAndOrderFront(nil)
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		try await settleLayout(controller.view)
		let table = try #require(fileTable(in: controller.view))
		let scrollView = try #require(table.enclosingScrollView)
		let clip = scrollView.contentView
		try #require(window.makeFirstResponder(table))
		try #require(table.selectedRow == 0)
		let viewportHeight = fileViewport(in: table, headerHeight: 0).height

		let trace = ScrollTrace()
		let postsBoundsChangedNotifications = clip.postsBoundsChangedNotifications
		clip.postsBoundsChangedNotifications = true
		defer { clip.postsBoundsChangedNotifications = postsBoundsChangedNotifications }
		let observer = NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
		) { _ in
			MainActor.assumeIsolated { trace.offsets.append(clip.bounds.minY) }
		}
		defer { NotificationCenter.default.removeObserver(observer) }
		for direction in [1, -1] {
			trace.offsets = [clip.bounds.minY]
			for index in 0..<140 {
				if index == 65 {
					model.apply(
						snapshot(direction > 0 ? refreshedFiles : files), repositoryURL: repositoryURL)
				}
				try pressArrow(direction, in: table, isARepeat: index > 0)
				try await Task.sleep(for: .milliseconds(16))
			}
			try await settleLayout(controller.view, passes: 30)
			let expectedRow = direction > 0 ? files.count - 1 : 0
			#expect(fileTable(in: controller.view) === table)
			try #require(table.selectedRow == expectedRow)
			#expect(model.selectedTreeNodeID == files[expectedRow].id)
			try #require(trace.offsets.count > 2)
			let reversed = zip(trace.offsets, trace.offsets.dropFirst()).filter {
				($0.1 - $0.0) * CGFloat(direction) < -1
			}
			#expect(reversed.isEmpty, "direction \(direction), reversed scroll \(reversed.prefix(10))")
			let selectedRow = table.rect(ofRow: table.selectedRow)
			let viewport = fileViewport(in: table, headerHeight: 0)
			#expect(abs(viewport.height - viewportHeight) < 1)
			#expect(selectedRow.minY >= viewport.minY - 1 && selectedRow.maxY <= viewport.maxY + 1)
		}
	}

	@MainActor
	private final class ScrollTrace {
		var offsets: [CGFloat] = []
	}

	private func pressArrow(_ direction: Int, in table: NSTableView, isARepeat: Bool = false) throws {
		let window = try #require(table.window)
		let characters = direction > 0 ? "\u{F701}" : "\u{F700}"
		let event = try #require(
			NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				characters: characters, charactersIgnoringModifiers: characters,
				isARepeat: isARepeat, keyCode: direction > 0 ? 125 : 126))
		window.sendEvent(event)
	}

	private func settleLayout(_ view: NSView, passes: Int = 10) async throws {
		for _ in 0..<passes {
			view.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func fileTable(in view: NSView) -> NSTableView? {
		if let table = view as? NSTableView, table.numberOfRows >= 80 { return table }
		return view.subviews.lazy.compactMap { fileTable(in: $0) }.first
	}

	private func fileViewport(in table: NSTableView, headerHeight: CGFloat) -> NSRect {
		let insets = table.enclosingScrollView?.contentInsets ?? NSEdgeInsets()
		let visible = table.visibleRect
		return NSRect(
			x: visible.minX, y: visible.minY + insets.top + headerHeight,
			width: visible.width, height: visible.height - insets.top - insets.bottom - headerHeight)
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func makeSnapshot(changes: [WorkingTreeChange]) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: [],
			commits: [],
			branches: [],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)
	}
}
