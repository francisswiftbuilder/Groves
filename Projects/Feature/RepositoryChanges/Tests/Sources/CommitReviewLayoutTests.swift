import AppKit
import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import SwiftUI
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct CommitReviewLayoutTests {
	private struct PlanningUseCase: RepositoryCommitPlanningUseCase {
		let plan: GitCommitPlan
		var scenario = "review"

		func loadPlan(at repositoryURL: URL) async throws -> GitCommitPlan {
			if scenario == "failure" {
				throw GitCommitPlanError.modelUnavailable("Fixture model unavailable")
			}
			if scenario == "preparing" || scenario == "analyzing" {
				try await Task.sleep(for: .seconds(30))
			}
			return plan
		}
		func loadPlan(
			at repositoryURL: URL, progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
		) async throws -> GitCommitPlan {
			if scenario == "analyzing" {
				await progress(.init(phase: .analyzing, completed: 12, total: 45))
			}
			return try await loadPlan(at: repositoryURL)
		}
		func commit(_ task: GitCommitTask, from plan: GitCommitPlan, at repositoryURL: URL) async throws
			-> GitCommitPlanInput
		{
			throw GitCommitPlanError.invalidPlan
		}
	}
	private struct Probe: NSViewRepresentable {
		let name: String

		func makeNSView(context: Context) -> NSView {
			let view = NSView()
			view.identifier = NSUserInterfaceItemIdentifier(name)
			return view
		}

		func updateNSView(_ view: NSView, context: Context) {}
	}

	@Test(arguments: [600.0, 700.0, 850.0])
	func nestedReviewPanesStayBetweenTheirInsetBars(height: Double) async throws {
		let content = CommitReviewContainer {
			HStack(spacing: 0) {
				List {
					Text("First task").frame(height: 28).background { Probe(name: "first-row") }
					ForEach(1..<12) { index in Text("Task \(index)") }
				}
				.frame(width: 240)
				Divider()
				CommitReviewContainer {
					Color.clear.background { Probe(name: "diff") }
				} header: {
					TextField("Summary", text: .constant("fix: review changes"))
						.frame(height: 120).background { Probe(name: "editor") }
				} footer: {
					EmptyView()
				}
			}
			.background { Probe(name: "review") }
		} header: {
			Text("Organize Commits").frame(maxWidth: .infinity).frame(height: 100)
				.background { Probe(name: "header") }
		} footer: {
			Text("Commit Task").frame(maxWidth: .infinity).frame(height: 60)
				.background { Probe(name: "footer") }
		}
		.frame(width: 980, height: height)
		let host = NSHostingView(rootView: content)
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 980, height: height),
			styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		defer { window.close() }
		for _ in 0..<30 {
			host.layoutSubtreeIfNeeded()
			if let diff = bounds(named: "diff", in: host), diff.height > 0 { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		let header = try #require(bounds(named: "header", in: host))
		let footer = try #require(bounds(named: "footer", in: host))
		let review = try #require(bounds(named: "review", in: host))
		let editor = try #require(bounds(named: "editor", in: host))
		let diff = try #require(bounds(named: "diff", in: host))
		let firstRow = try #require(bounds(named: "first-row", in: host))
		#expect(abs(review.height - (height - 160)) < 2)
		#expect(!header.insetBy(dx: 1, dy: 1).intersects(review))
		#expect(!footer.insetBy(dx: 1, dy: 1).intersects(review))
		#expect(review.insetBy(dx: -1, dy: -1).contains(editor))
		#expect(review.insetBy(dx: -1, dy: -1).contains(firstRow))
		#expect(!editor.insetBy(dx: 1, dy: 1).intersects(diff))
	}

	private func bounds(named name: String, in host: NSView) -> CGRect? {
		func find(in view: NSView) -> NSView? {
			if view.identifier?.rawValue == name { return view }
			return view.subviews.lazy.compactMap { find(in: $0) }.first
		}
		guard let view = find(in: host) else { return nil }
		return host.convert(view.bounds, from: view)
	}

	@Test(arguments: [900.0, 1400.0])
	func centerPaneKeepsItsBodyTextAndToolbarInsideTheAppKitSplit(width: Double) async throws {
		let center = VStack(spacing: 0) {
			ContentUnavailableView {
				Label {
					Text("11 Changes Selected").background { Probe(name: "summary-title") }
				} icon: {
					Image(systemName: "doc.on.doc")
				}
				.background { Probe(name: "summary-label") }
			} description: {
				Text("Use Stage or Unstage above to apply your selection.")
					.background { Probe(name: "summary-description") }
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .top, spacing: 0) {
			HStack {
				Text("11 Changes Selected").background { Probe(name: "toolbar-title") }
				Spacer(minLength: 0)
				Button("Stage") {}.background { Probe(name: "toolbar-action") }
			}
			.padding(.horizontal, 12)
			.frame(height: 52)
			.background { Probe(name: "toolbar") }
		}
		.background { Probe(name: "center-pane") }
		let host = NSHostingView(
			rootView: EqualWidthHSplitView(
				proportions: [0.27, 0.5, 0.23], minimumWidths: [200, 300, 170]
			) {
				Text("Files")
			} center: {
				center
			} trailing: {
				Text("Inspector")
			}.frame(width: width, height: 600))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		defer { window.close() }
		for _ in 0..<20 {
			host.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(10))
		}
		let pane = try #require(bounds(named: "center-pane", in: host))
		let toolbar = try #require(bounds(named: "toolbar", in: host))
		let toolbarTitle = try #require(bounds(named: "toolbar-title", in: host))
		let action = try #require(bounds(named: "toolbar-action", in: host))
		let title = try #require(bounds(named: "summary-title", in: host))
		let label = try #require(bounds(named: "summary-label", in: host))
		let description = try #require(bounds(named: "summary-description", in: host))
		#expect(pane.width >= 300)
		#expect(pane.insetBy(dx: -1, dy: -1).contains(toolbar))
		#expect(toolbar.insetBy(dx: -1, dy: -1).contains(toolbarTitle))
		#expect(toolbar.insetBy(dx: -1, dy: -1).contains(action))
		#expect(toolbarTitle.minX - pane.minX >= 11)
		#expect(pane.maxX - action.maxX >= 11)
		#expect(title.width > 50 && title.height > 10)
		#expect(pane.contains(title))
		#expect(pane.contains(description))
		#expect(!toolbar.insetBy(dx: 1, dy: 1).intersects(title))
		#expect(abs(label.midX - pane.midX) < 2)
	}

	@Test(arguments: [900.0, 1400.0], [false, true])
	func renderChangesListWithPartialStagingAndScrolling(width: Double, multiple: Bool) async throws {
		let changes: [WorkingTreeChange] =
			[
				.init(
					path: "Sources/FoundationModelCommitPlanGenerator.swift", previousPath: nil,
					indexState: .modified, workingTreeState: .modified),
				.init(
					path: "Sources/CommitPlan.swift", previousPath: nil, indexState: .added,
					workingTreeState: .unchanged),
			]
			+ (1...24).map {
				.init(
					path: "Tests/Change\($0)Tests.swift", previousPath: nil, indexState: .unchanged,
					workingTreeState: .untracked)
			}
		let viewModel = ChangesViewModel(
			dependencies: .init(
				contentUseCase: ChangesContentUseCaseStub(), changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/ReviewFixture") }),
			actions: .init(
				didProduceSnapshot: { _ in }, didReceiveError: { _ in }, didSelectConflict: { _ in },
				didSelectDiff: { _, _ in }))
		viewModel.apply(
			.init(
				changes: changes, amendChanges: [], commits: [], branches: [], remotes: [],
				operationState: .normal, tags: [], stashes: [], fileTree: []))
		#expect(viewModel.filteredStagedChanges.count == 2)
		#expect(viewModel.filteredUnstagedChanges.count == 25)
		if multiple {
			await viewModel.didSelectChanges([.unstaged(changes[0].id), .unstaged(changes[2].id)])
		}
		let conflictViewModel = ConflictViewModel(
			dependencies: .init(
				contentUseCase: ChangesContentUseCaseStub(),
				operationsUseCase: ConflictOperationsUseCaseStub(), openExternalEditor: nil,
				repositoryURL: { nil }, externalEditorBundleIdentifier: { nil }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: { _ in }))
		let preferences = WorkspaceDiffPreferences()
		let diffViewModel = ChangesDiffViewModel(
			dependencies: .init(
				changesUseCase: ChangesUseCaseStub(diffOperation: { _, _, _, _ in
					"diff --git a/Example.swift b/Example.swift\n--- a/Example.swift\n+++ b/Example.swift\n@@ -1 +1 @@\n-let value = 1\n+let value = 2\n"
				}), preferences: preferences, repositoryURL: { URL(fileURLWithPath: "/tmp/ReviewFixture") }),
			actions: .init(didApplyMutation: { _, _, _ in }, didReceiveError: { _ in }))
		if !multiple, let selection = viewModel.selectedChangeIDs.first {
			diffViewModel.didSelect(.workingTree(selection, changes[0], .staged))
			for _ in 0..<100 {
				if !diffViewModel.isLoading { break }
				try await Task.sleep(for: .milliseconds(1))
			}
			#expect(!diffViewModel.diff.isEmpty)
		}
		defer { diffViewModel.onDisappear() }
		let commitViewModel = CommitViewModel(
			dependencies: .init(
				contentUseCase: ChangesContentUseCaseStub(), changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/ReviewFixture") },
				commitPlanningUseCase: PlanningUseCase(
					plan: .init(
						input: .init(headHash: "head", indexFingerprint: "index", units: []), tasks: [],
						model: .onDevice))),
			actions: .init(
				didProduceSnapshot: { _ in }, didReceiveError: { _ in }, didChangeAmendingCommit: { _ in }))
		commitViewModel.apply(
			.init(
				changes: changes, amendChanges: [], commits: [], branches: [], remotes: [],
				operationState: .normal, tags: [], stashes: [], fileTree: []))
		defer { commitViewModel.onDisappear() }
		let controller = NSHostingController(
			rootView: EqualWidthHSplitView(
				proportions: [0.27, 0.5, 0.23], minimumWidths: [200, 300, 170]
			) {
				ChangesListView(
					viewModel: viewModel, conflictViewModel: conflictViewModel, repositoryURL: nil
				)
			} center: {
				ChangesDiffPane(
					searchViewModel: RepositorySearchViewModel(), viewModel: viewModel,
					diffViewModel: diffViewModel,
					conflictViewModel: conflictViewModel, preferences: preferences, repositoryURL: nil,
					onOptionsChanged: {}
				)
				.frame(minWidth: 300, maxWidth: .infinity)
			} trailing: {
				ChangesInspectorPane(viewModel: viewModel, diffViewModel: diffViewModel)
			}
			.safeAreaInset(edge: .bottom, spacing: 0) { CommitBar(viewModel: commitViewModel) }
			.frame(width: width, height: 520)
			.background { Color(nsColor: .windowBackgroundColor) }
			.environment(\.colorScheme, .dark))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 520), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .darkAqua)
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		let host = controller.view
		host.appearance = NSAppearance(named: .darkAqua)
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		for _ in 0..<10 {
			host.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(20))
		}
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(
			to: URL(
				fileURLWithPath:
					"/tmp/groves-selection-flow-\(Int(width))-\(multiple ? "multiple" : "single").png"))
	}

	@Test(arguments: ["review", "preparing", "analyzing", "failure"], [ColorScheme.light, .dark])
	func renderReviewSheetWithLongMessagesAndPaths(scenario: String, colorScheme: ColorScheme)
		async throws
	{
		let path =
			"Projects/Feature/RepositoryChanges/Sources/ViewModel/RepositoryCommitPlanningViewModel.swift"
		let unit = GitCommitUnit(
			id: "preview", path: path,
			patch:
				"diff --git a/Example.swift b/Example.swift\n--- a/Example.swift\n+++ b/Example.swift\n@@ -1 +1 @@\n-let value = 1\n+let value = 2\n",
			hunk: .init(oldStartLine: 1, newStartLine: 1))
		let plan = GitCommitPlan(
			input: .init(headHash: "head", indexFingerprint: "index", units: [unit]),
			tasks: [
				.init(
					subject: "fix(review): 긴 파일 경로와 여러 줄 커밋 설명을 검토 화면에 표시",
					body: "- 상단 메시지 입력 영역 배치\n- 하단 버튼과 diff 영역 분리\n- 긴 경로 표시 처리", unitIDs: [unit.id])
			],
			model: .onDevice)
		let viewModel = CommitPlanViewModel(
			dependencies: .init(
				useCase: PlanningUseCase(plan: plan, scenario: scenario),
				contentUseCase: ChangesContentUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/ReviewFixture") }),
			didProduceSnapshot: { _ in })
		viewModel.apply(
			.init(
				changes: [
					.init(path: path, previousPath: nil, indexState: .modified, workingTreeState: .unchanged)
				],
				amendChanges: [], commits: [], branches: [], remotes: [], operationState: .normal,
				tags: [], stashes: [], fileTree: []))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		for _ in 0..<50 {
			if scenario == "preparing" { break }
			if scenario == "analyzing", viewModel.analysisProgress != nil { break }
			if !viewModel.isGenerating { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		if scenario == "review" { #expect(viewModel.plan?.isValid == true) }
		if scenario == "analyzing" { #expect(viewModel.analysisProgress?.completed == 12) }
		if scenario == "failure" { #expect(viewModel.errorMessage != nil) }
		let controller = NSHostingController(
			rootView: CommitPlanSheet(viewModel: viewModel)
				.background { Color(nsColor: .windowBackgroundColor) }
				.environment(\.colorScheme, colorScheme))
		let size =
			scenario == "review" ? CGSize(width: 980, height: 700) : CGSize(width: 460, height: 240)
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		let host = controller.view
		host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		window.appearance = host.appearance
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		for _ in 0..<10 {
			host.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(20))
		}
		if scenario == "review" {
			let viewport = try #require(
				scrollViews(in: host).first { scrollView in
					let rect = host.convert(scrollView.bounds, from: scrollView)
					return rect.minX >= 250 && rect.width > 300 && rect.height > 120
				})
			let rect = host.convert(viewport.bounds, from: viewport)
			#expect(host.bounds.insetBy(dx: -1, dy: -1).contains(rect))
			#expect(rect.height > 300)
			let document = try #require(viewport.documentView)
			#expect(document.frame.height > 40)
			#expect(viewport.contentView.bounds.intersects(document.frame))
		}
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(
			to: URL(
				fileURLWithPath:
					"/tmp/groves-commit-\(scenario)-\(colorScheme == .dark ? "dark" : "light").png"))
	}

	private func scrollViews(in view: NSView) -> [NSScrollView] {
		(view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
	}
}
