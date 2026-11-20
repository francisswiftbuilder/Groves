import AppKit
import DomainGitInterface
import SwiftUI
import Testing

@testable import CoreGitCredential
@testable import Pluminon

@MainActor
struct SidebarSettingsLayoutTests {
	@Test(
		arguments: [
			(180.0, 0), (180.0, 1), (180.0, 2), (220.0, 0), (220.0, 1), (220.0, 2), (280.0, 0),
			(280.0, 1), (280.0, 2),
		],
		[ColorScheme.light, .dark])
	func sidebarSectionsCollapseWithoutChangingTheSelectedDestination(
		configuration: (Double, Int), colorScheme: ColorScheme
	) async throws {
		let (width, remoteCount) = configuration
		let workspace = makeRepositoryWorkspace()
		let repositoryID = UUID()
		let remotes = ["origin", "upstream"].prefix(remoteCount).map { name in
			GitRemote(
				name: name, fetchURL: "https://example.com/\(name).git", pushURL: nil,
				branches: ["main", "develop", "feat/repository-sidebar-and-account-settings"].map {
					branch in
					GitRemoteBranch(
						name: branch, fullName: "\(name)/\(branch)", remoteName: name,
						shortHash: "abcdef0", hash: "abcdef0")
				})
		}
		workspace.viewModel.didProduceSnapshot(
			.init(
				changes: [
					.init(
						path: "Sources/Example.swift", previousPath: nil, indexState: .modified,
						workingTreeState: .unchanged)
				],
				amendChanges: [], commits: [],
				branches: [
					.init(
						name: "feat/repository-sidebar-and-account-settings", shortHash: "abcdef1",
						upstream: "origin/feat/repository-sidebar-and-account-settings",
						aheadCount: 2, behindCount: 1, isCurrent: true),
					.init(name: "main", shortHash: "abcdef0", upstream: "origin/main", isCurrent: false),
				],
				remotes: remotes,
				operationState: .normal,
				tags: [
					.init(
						name: "v1.1.1", shortHash: "abcdef0", targetHash: "abcdef0", date: nil,
						subject: "Release")
				],
				stashes: [
					.init(
						reference: "stash@{0}", hash: "1234567", subject: "WIP: Repository settings", date: .now
					)
				], fileTree: []))
		let windowModel = RepositoryWindowViewModel()
		let selection = RepositorySidebarSelection.section(
			repositoryID: repositoryID, section: .changes)
		windowModel.selectSidebarItem(selection)
		let sidebar = RepositorySidebar(
			viewModel: workspace.viewModel, windowViewModel: windowModel,
			changesViewModel: workspace.changesViewModel,
			operationViewModel: workspace.operationViewModel,
			referencesViewModel: workspace.referencesViewModel,
			remotesViewModel: workspace.remotesViewModel, stashesViewModel: workspace.stashesViewModel,
			repositoryID: repositoryID)
		let controller = NSHostingController(rootView: AnyView(EmptyView()))
		let window = makeWindow(
			controller: controller, size: .init(width: width, height: 680), colorScheme: colorScheme)
		controller.rootView = AnyView(
			sidebar.frame(width: width, height: 680).environment(\.colorScheme, colorScheme))
		defer {
			close(window: window, controller: controller)
			workspace.onDisappear()
		}
		try await settle(controller.view)
		let outlineView = try #require(outline(in: controller.view))
		let expandedCount = outlineView.numberOfRows
		try capture(
			controller.view, name: "sidebar-\(Int(width))-\(colorScheme)-\(remoteCount)-remotes")
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: .branches)
		workspace.viewModel.setSidebarGroup(group, isExpanded: false)
		try await settle(controller.view)
		#expect(outlineView.numberOfRows < expandedCount)
		#expect(windowModel.sidebarSelection == selection)
		workspace.viewModel.didPrepareSidebar(repositoryID: repositoryID)
		#expect(!workspace.viewModel.expandedSidebarGroups.contains(group))
		let beforeRemoteCollapse = outlineView.numberOfRows
		workspace.viewModel.setSidebarGroup(
			.init(repositoryID: repositoryID, kind: .remotes), isExpanded: false)
		try await settle(controller.view)
		#expect(beforeRemoteCollapse - outlineView.numberOfRows == remotes.flatMap(\.branches).count)
		#expect(windowModel.sidebarSelection == selection)
		let beforeStashCollapse = outlineView.numberOfRows
		workspace.viewModel.setSidebarGroup(
			.init(repositoryID: repositoryID, kind: .stashes), isExpanded: false)
		try await settle(controller.view)
		#expect(
			beforeStashCollapse - outlineView.numberOfRows == workspace.stashesViewModel.stashes.count)
		#expect(windowModel.sidebarSelection == selection)
	}

	@Test(
		arguments: [
			"general", "grouped", "tabBar", "nativeTabs", "accounts", "emptyAccounts", "add", "replace",
			"onboarding",
		],
		[ColorScheme.light, .dark])
	func settingsKeepEditableFieldsInsideTheWindow(scenario: String, colorScheme: ColorScheme)
		async throws
	{
		let suite = "Pluminon.Settings.Layout.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set("Developer", forKey: "isolatedGitAuthorName")
		defaults.set("developer@example.com", forKey: "isolatedGitAuthorEmail")
		let store = GitCredentialStore(
			service: suite, securityClient: GitAccountViewModelTests.SecurityClientStub(),
			accessGroupResolver: { "TESTTEAM.Pluminon.Settings.Layout" })
		if scenario != "emptyAccounts" && scenario != "onboarding" {
			try store.save(
				secret: "fixture", for: .init(kind: .https, host: "github.com", account: "developer"))
		}
		let directory = FileManager.default.temporaryDirectory.appending(path: suite)
		defer { try? FileManager.default.removeItem(at: directory) }
		let viewModel = GitAccountViewModel(
			store: store, defaults: defaults, configurationURL: directory.appending(path: "config"))
		viewModel.load()
		if scenario == "add" { viewModel.beginAddingAccount() }
		if scenario == "replace" { viewModel.beginReplacingToken() }
		defer { viewModel.cancelTokenEntry() }
		let size: CGSize
		let view: AnyView
		switch scenario {
		case "general":
			size = .init(width: 540, height: 420)
			view = AnyView(GeneralSettingsView(accountViewModel: viewModel))
		case "add", "replace":
			size = .init(width: 480, height: 280)
			view = AnyView(GitAccountTokenSheet(viewModel: viewModel))
		case "onboarding":
			size = .init(width: 540, height: 440)
			view = AnyView(GitAccountSetupView(viewModel: viewModel, isOnboarding: true))
		default:
			size = .init(width: 540, height: 280)
			view = AnyView(GitAccountSetupView(viewModel: viewModel, isOnboarding: false))
		}
		let controller = NSHostingController(rootView: AnyView(EmptyView()))
		let window = makeWindow(controller: controller, size: size, colorScheme: colorScheme)
		controller.rootView = AnyView(
			view
				.frame(width: size.width, height: size.height)
				.defaultAppStorage(defaults)
				.background { Color(nsColor: .windowBackgroundColor) }
				.environment(\.colorScheme, colorScheme))
		defer { close(window: window, controller: controller) }
		try await settle(controller.view)
		let fields = editableFields(in: controller.view)
		if ["general", "add", "replace", "onboarding"].contains(scenario) { #expect(!fields.isEmpty) }
		for field in fields {
			let rect = controller.view.convert(field.bounds, from: field)
			#expect(controller.view.bounds.insetBy(dx: 12, dy: 12).contains(rect))
		}
		try capture(controller.view, name: "settings-\(scenario)-\(colorScheme)")
	}

	@Test(arguments: [680.0, 760.0, 1_280.0], [ColorScheme.light, .dark])
	func newTabShowsTheRepositoryListAndFitsTheSearchField(
		width: Double, colorScheme: ColorScheme
	) async throws {
		let suite = "Pluminon.NewTab.Layout.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = GitCredentialStore(
			service: suite, securityClient: GitAccountViewModelTests.SecurityClientStub(),
			accessGroupResolver: { "TESTTEAM.Pluminon.NewTab.Layout" })
		try store.save(
			secret: "valid-test-token", for: .init(kind: .https, host: "github.com", account: "octocat"))
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [GitAccountViewModelTests.AuthenticationURLProtocol.self]
		let account = GitAccountViewModel(
			store: store, client: .init(session: URLSession(configuration: configuration)),
			defaults: defaults)
		account.load()
		let size = CGSize(width: width, height: 520)
		let controller = NSHostingController(rootView: AnyView(EmptyView()))
		let window = makeWindow(controller: controller, size: size, colorScheme: colorScheme)
		window.styleMask.insert(.titled)
		window.makeKeyAndOrderFront(nil)
		controller.rootView = AnyView(
			RepositoryWelcomeContainerView(
				accountViewModel: account, repositories: [], isWorking: false, onOpenRepository: {},
				onOpenSavedRepository: { _ in }, onCloneRepository: { _ in }, onCancel: {}
			)
			.frame(width: size.width, height: size.height)
			.environment(\.colorScheme, colorScheme))
		defer { close(window: window, controller: controller) }
		try await settle(controller.view)

		let fields = editableFields(in: controller.view)
		try #require(!fields.isEmpty)
		for field in fields {
			#expect(controller.view.bounds.contains(controller.view.convert(field.bounds, from: field)))
		}
		#expect(tableRowCounts(in: controller.view).contains(1))
		var captureResult: Result<Void, any Error> = .success(())
		window.effectiveAppearance.performAsCurrentDrawingAppearance {
			captureResult = Result {
				try capture(controller.view, name: "new-tab-\(Int(width))-\(colorScheme)")
			}
		}
		try captureResult.get()

		let searchField = try #require(fields.first)
		let originalTable = try #require(repositoryTable(in: controller.view))
		let ancestors = sequence(first: originalTable as NSView, next: { $0.superview })
		let split = try #require(ancestors.compactMap { $0 as? NSSplitView }.first)
		let previewPane = try #require(split.subviews.last)
		try #require(window.makeFirstResponder(originalTable))
		originalTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		try await settle(controller.view)
		try #require(window.makeFirstResponder(searchField))
		for (character, keyCode, expectedText) in [
			("i", UInt16(34), "i"), ("x", UInt16(7), "ix"), ("z", UInt16(6), "ixz"),
			("\u{7f}", UInt16(51), "ix"), ("\u{7f}", UInt16(51), "i"),
		] {
			let event = try #require(
				NSEvent.keyEvent(
					with: .keyDown, location: .zero, modifierFlags: [],
					timestamp: ProcessInfo.processInfo.systemUptime,
					windowNumber: window.windowNumber, context: nil,
					characters: character, charactersIgnoringModifiers: character,
					isARepeat: false, keyCode: keyCode))
			window.sendEvent(event)
			try await settle(controller.view)
			let editor = try #require(
				searchField.currentEditor(), "Search lost focus after \(expectedText)")
			#expect(window.firstResponder === editor)
			#expect(editor.string == expectedText)
			#expect(split.isDescendant(of: controller.view))
			#expect(split.subviews.last === previewPane)
		}

		let table = try #require(repositoryTable(in: controller.view))
		try #require(window.makeFirstResponder(table))
		#expect(table.selectedRow == 0)
		let firstRow = controller.view.convert(table.rect(ofRow: 0), from: table)
		let searchBounds = controller.view.convert(searchField.bounds, from: searchField)
		#expect(firstRow.minY >= searchBounds.maxY)
		try capture(controller.view, name: "new-tab-preview-\(Int(width))-\(colorScheme)")
	}

	@Test
	func newTabCanSubmitAPublicCloneURLWithoutAGitHubAccount() async throws {
		let suite = "Pluminon.CloneSearch.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let account = GitAccountViewModel(defaults: defaults)
		var cloneRequests: [String] = []
		let size = CGSize(width: 760, height: 520)
		let controller = NSHostingController(rootView: AnyView(EmptyView()))
		let window = makeWindow(controller: controller, size: size, colorScheme: .light)
		window.styleMask.insert(.titled)
		window.makeKeyAndOrderFront(nil)
		controller.rootView = AnyView(
			RepositoryWelcomeContainerView(
				accountViewModel: account, repositories: [], isWorking: false, onOpenRepository: {},
				onOpenSavedRepository: { _ in }, onCloneRepository: { cloneRequests.append($0) },
				onCancel: {}
			)
			.frame(width: size.width, height: size.height))
		defer { close(window: window, controller: controller) }
		try await settle(controller.view)

		let field = try #require(editableFields(in: controller.view).first)
		#expect(field.isEnabled)
		try #require(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)
		let url = "https://gitlab.com/example/project.git"
		editor.insertText(url, replacementRange: NSRange(location: NSNotFound, length: 0))
		try await settle(controller.view)
		#expect(window.firstResponder === editor)
		#expect(cloneRequests.isEmpty)
		let event = try #require(
			NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
				context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
				isARepeat: false, keyCode: 36))
		window.sendEvent(event)
		try await settle(controller.view)
		#expect(cloneRequests == [url])
	}

	@Test(arguments: [760.0, 1_280.0], [ColorScheme.light, .dark])
	func repositoryToolbarFitsNarrowAndWideWindows(
		width: Double, colorScheme: ColorScheme
	)
		async throws
	{
		let workspace = makeRepositoryWorkspace()
		workspace.viewModel.didProduceSnapshot(
			.init(
				changes: [], amendChanges: [], commits: [],
				branches: [
					.init(name: "main", shortHash: "abcdef0", upstream: "origin/main", isCurrent: true)
				],
				remotes: [.init(name: "origin", fetchURL: "https://example.com/repo.git", pushURL: nil)],
				operationState: .normal, tags: [], stashes: [], fileTree: []))
		let controller = NSHostingController(
			rootView: NavigationSplitView {
				Text("Repository").navigationSplitViewColumnWidth(220)
			} detail: {
				Color(nsColor: .textBackgroundColor)
			}
			.navigationTitle("Pluminon")
			.toolbar {
				RepositoryWorkspaceToolbar(
					viewModel: workspace.viewModel, operationViewModel: workspace.operationViewModel,
					referencesViewModel: workspace.referencesViewModel,
					syncViewModel: workspace.syncViewModel,
					remotesViewModel: workspace.remotesViewModel, onCreateBranch: {})
			}
			.toolbarRole(.editor)
			.frame(minWidth: width, minHeight: 520))
		let window = NSWindow(
			contentRect: .init(x: 0, y: 0, width: width, height: 520),
			styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
			defer: false)
		window.isReleasedWhenClosed = false
		controller.sizingOptions = []
		window.toolbarStyle = .unified
		window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		defer {
			close(window: window, controller: controller)
			workspace.onDisappear()
		}
		try await settle(controller.view)
		#expect(window.contentLayoutRect.width >= width)
		let toolbar = try #require(window.toolbar)
		#expect(toolbar.isVisible)
		for item in toolbar.visibleItems ?? [] {
			if let view = item.view {
				#expect(view.frame.width > 0)
			}
		}
		let frameView = try #require(window.contentView?.superview)
		try capture(frameView, name: "toolbar-\(Int(width))-\(colorScheme)")
	}

	private func makeWindow<Content: View>(
		controller: NSHostingController<Content>, size: CGSize, colorScheme: ColorScheme
	) -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
			defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		controller.sizingOptions = []
		window.contentViewController = controller
		controller.view.frame = NSRect(origin: .zero, size: size)
		controller.view.appearance = window.appearance
		controller.viewWillAppear()
		controller.viewDidAppear()
		return window
	}

	private func close<Content: View>(window: NSWindow, controller: NSHostingController<Content>) {
		controller.viewWillDisappear()
		controller.viewDidDisappear()
		window.close()
	}

	private func settle(_ view: NSView) async throws {
		for _ in 0..<10 {
			view.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(20))
		}
	}

	private func capture(_ view: NSView, name: String) throws {
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(in: view.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(to: URL(fileURLWithPath: "/tmp/pluminon-\(name).png"))
	}

	private func outline(in view: NSView) -> NSOutlineView? {
		if let outline = view as? NSOutlineView { return outline }
		return view.subviews.lazy.compactMap { outline(in: $0) }.first
	}

	private func editableFields(in view: NSView) -> [NSTextField] {
		if let field = view as? NSTextField, field.isEditable { return [field] }
		return view.subviews.flatMap { editableFields(in: $0) }
	}

	private func tableRowCounts(in view: NSView) -> [Int] {
		let ownCount = (view as? NSTableView).map { [$0.numberOfRows] } ?? []
		return ownCount + view.subviews.flatMap { tableRowCounts(in: $0) }
	}

	private func repositoryTable(in view: NSView) -> NSTableView? {
		if let table = view as? NSTableView, table.numberOfRows == 1 { return table }
		return view.subviews.lazy.compactMap { repositoryTable(in: $0) }.first
	}
}
