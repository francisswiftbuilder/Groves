import DomainGitInterface
import Foundation
import Testing

@testable import CoreRepositoryDiff
@testable import FeatureRepositoryChanges
@testable import Groves

@MainActor
struct DiffPresentationContractTests {
	@Test
	func testLayoutChangeDoesNotRequestTheDiffAgain() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				unstagedDiff: Self.diff(lineCount: 8),
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { await gate.callCount(of: label) == 1 }
		let searchModel = workspace.changesDiffSearchViewModel
		searchModel.update(
			sources: [RepositorySearchSource(id: 1, text: "layout search state")]
		)
		searchModel.query = "search"
		try await waitUntil { searchModel.matches.count == 1 }
		let selectedMatch = searchModel.currentMatch

		workspace.diffPreferences.presentationMode = .sideBySide
		workspace.diffPreferences.presentationMode = .unified
		try await Task.sleep(for: .milliseconds(150))

		let callCount = await gate.callCount(of: label)
		#expect(callCount == 1, "Switching layout must not reload the diff")
		#expect(searchModel.query == "search")
		#expect(searchModel.currentMatch == selectedMatch)
	}

	@Test
	func testSingleParseProducesBothLayouts() async throws {
		let model = DiffViewerViewModel()

		await model.update(diff: Self.diff(lineCount: 40))

		#expect(!(model.isParsing))
		#expect(!(model.presentation?.document.lines.isEmpty == true))
		#expect(
			!(model.presentation?.sideBySideRows.isEmpty == true),
			"Both layouts must be ready after one parse, so switching layout needs no work")
	}

	@Test
	func testParsingPublishesTheExactCompletedPresentation() async {
		let model = DiffViewerViewModel()
		let input = DiffViewerViewModel.Input(
			sourceID: "unstaged:Sources/App.swift",
			filePath: "Sources/App.swift",
			diff: Self.diff(lineCount: 20)
		)

		#expect(!(model.hasParsed(input)))
		#expect(model.presentation == nil)

		await model.update(input: input)

		#expect(model.hasParsed(input))
		#expect(model.canInteract(with: input))
		#expect(model.presentation?.input == input)
		#expect(!(model.presentation?.document.lines.isEmpty == true))
		#expect(!(model.presentation?.sideBySideRows.isEmpty == true))
	}

	@Test
	func testMetadataOnlyInputBecomesEmptyOnlyAfterParseCompletes() async {
		let model = DiffViewerViewModel()
		let input = DiffViewerViewModel.Input(
			sourceID: "Binary.dat",
			diff: "diff --git a/Binary.dat b/Binary.dat\nindex 111..222 100644"
		)

		#expect(!(model.hasParsed(input)))

		await model.update(input: input)

		#expect(model.hasParsed(input))
		#expect(model.presentation?.document.lines.isEmpty == true)
	}

	@Test
	func testParsingAReplacementKeepsTheLastPresentationReadOnly() async throws {
		let model = DiffViewerViewModel()
		let initialInput = DiffViewerViewModel.Input(
			sourceID: "unstaged:Sources/App.swift",
			filePath: "Sources/App.swift",
			diff: Self.diff(lineCount: 20)
		)
		let replacementInput = DiffViewerViewModel.Input(
			sourceID: initialInput.sourceID,
			filePath: initialInput.filePath,
			diff: Self.diff(lineCount: 100_000)
		)
		await model.update(input: initialInput)
		let initialPresentation = model.presentation
		let initialRevision = model.presentation?.revision
		let replacementTask = Task {
			await model.update(input: replacementInput)
		}

		try await waitUntil { model.isParsing }

		#expect(model.presentation == initialPresentation)
		#expect(model.canInteract(with: initialInput))
		#expect(!(model.canInteract(with: replacementInput)))
		await replacementTask.value
		#expect(model.presentation != initialPresentation)
		#expect(model.presentation?.revision != initialRevision)
		#expect(model.presentation?.input == replacementInput)
		#expect(model.canInteract(with: replacementInput))
	}

	@Test
	func testAutomaticSnapshotRefreshKeepsTheSelectedDiffVisible() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let diff = Self.diff(lineCount: 8)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				unstagedDiff: diff,
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { await gate.callCount(of: label) == 1 }
		await gate.resumeCall(0)
		try await waitUntil { workspace.changesDiffViewModel.diff == diff }

		workspace.viewModel.didProduceSnapshot(
			RepositorySnapshot(
				changes: [change],
				amendChanges: [],
				commits: [],
				branches: [],
				remotes: [],
				operationState: .normal,
				tags: [],
				stashes: [],
				fileTree: []
			)
		)
		try await waitUntil { await gate.callCount(of: label) == 2 }

		#expect(workspace.changesDiffViewModel.diff == diff)
		#expect(workspace.changesDiffViewModel.isLoading)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.isLoading == false }

		let callCount = await gate.callCount(of: label)
		#expect(callCount == 2)
		#expect(workspace.changesDiffViewModel.diff == diff)
	}

	@Test
	func testSearchStateSurvivesAnIdenticalSourceUpdate() async throws {
		let model = RepositorySearchViewModel()
		let sources = [
			RepositorySearchSource(id: 1, text: "timeout and timeout"),
			RepositorySearchSource(id: 2, text: "timeout"),
		]
		model.update(sources: sources)
		model.query = "timeout"
		try await waitUntil { model.matches.count == 3 }
		model.next()
		let selectedMatch = model.currentMatch

		model.update(sources: sources)
		try await Task.sleep(for: .milliseconds(50))

		#expect(model.query == "timeout")
		#expect(model.matches.count == 3)
		#expect(
			model.currentMatch == selectedMatch,
			"Re-rendering the same diff must not reset the find selection")
	}

	@Test
	func testLayoutChangeKeepsCallerOwnedSearchState() async throws {
		let searchModel = RepositorySearchViewModel()
		let document = DiffDocument(lines: DiffParser.parse(Self.diff(lineCount: 8)))
		let sideBySideRows = DiffSideBySideBuilder.build(from: document)
		searchModel.update(
			sources: document.lines.map {
				RepositorySearchSource(id: $0.id, text: $0.sourceText)
			}
		)
		searchModel.query = "added"
		try await waitUntil { searchModel.matches.isEmpty == false }
		searchModel.next()
		let selectedMatch = searchModel.currentMatch

		let sideBySide = DiffViewer(
			searchModel: searchModel,
			document: document,
			sideBySideRows: sideBySideRows,
			presentationMode: .sideBySide,
			filePath: "Sources/App.swift",
			lineAction: nil,
			hunkActions: [],
			isApplyingAction: false,
			onApplyLine: { _, _ in },
			onApplyHunk: { _, _ in }
		)
		let unified = DiffViewer(
			searchModel: searchModel,
			document: document,
			sideBySideRows: sideBySideRows,
			presentationMode: .unified,
			filePath: "Sources/App.swift",
			lineAction: nil,
			hunkActions: [],
			isApplyingAction: false,
			onApplyLine: { _, _ in },
			onApplyHunk: { _, _ in }
		)

		#expect(sideBySide.searchModel === searchModel)
		#expect(unified.searchModel === searchModel)
		#expect(searchModel.query == "added")
		#expect(searchModel.currentMatch == selectedMatch)
	}

	@Test
	func testTenThousandLineDiffParsesOnce() async throws {
		try await assertLargeDiffParses(lineCount: 10_000)
	}

	@Test
	func testFiftyThousandLineDiffParsesOnce() async throws {
		try await assertLargeDiffParses(lineCount: 50_000)
	}

	private func assertLargeDiffParses(lineCount: Int) async throws {
		let change = WorkingTreeChange(
			path: "Large.swift",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate()
		let diff = Self.diff(lineCount: lineCount)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change], unstagedDiff: diff, diffGate: gate)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil(timeout: .seconds(10)) {
			workspace.changesDiffViewModel.diff == diff
		}

		let model = DiffViewerViewModel()
		await model.update(diff: diff)
		try await waitUntil(timeout: .seconds(20)) { model.isParsing == false }

		#expect(model.presentation?.document.lines.count == lineCount + 1)
		#expect(!(model.presentation?.sideBySideRows.isEmpty == true))
		let callCount = await gate.callCount(of: label)
		#expect(callCount == 1, "A single selection must issue a single diff request")
	}

	private static func diff(lineCount: Int) -> String {
		var lines = ["@@ -1,\(lineCount) +1,\(lineCount) @@"]
		for index in 0..<lineCount {
			switch index % 3 {
			case 0: lines.append("+let added\(index) = \(index)")
			case 1: lines.append("-let removed\(index) = \(index)")
			default: lines.append(" let context\(index) = \(index)")
			}
		}
		return lines.joined(separator: "\n")
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping () async -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await condition() == false {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
