import AppKit
import DomainGitInterface
import SwiftUI
import Testing

@testable import CoreGitCredential
@testable import Groves

@MainActor
struct SidebarSettingsLayoutTests {
	@Test(arguments: [180.0, 220.0, 280.0], [ColorScheme.light, .dark])
	func sidebarSectionsCollapseWithoutChangingTheSelectedDestination(
		width: Double, colorScheme: ColorScheme
	) async throws {
		let workspace = makeRepositoryWorkspace()
		let repositoryID = UUID()
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
				remotes: [
					.init(name: "origin", fetchURL: "https://example.com/repository.git", pushURL: nil)
				],
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
		try capture(controller.view, name: "sidebar-\(Int(width))-\(colorScheme)")
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: .branches)
		workspace.viewModel.setSidebarGroup(group, isExpanded: false)
		try await settle(controller.view)
		#expect(outlineView.numberOfRows < expandedCount)
		#expect(windowModel.sidebarSelection == selection)
		workspace.viewModel.didPrepareSidebar(repositoryID: repositoryID)
		#expect(!workspace.viewModel.expandedSidebarGroups.contains(group))
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
		let suite = "Groves.Settings.Layout.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set("Developer", forKey: "isolatedGitAuthorName")
		defaults.set("developer@example.com", forKey: "isolatedGitAuthorEmail")
		let store = GitCredentialStore(
			service: suite, securityClient: GitAccountViewModelTests.SecurityClientStub(),
			accessGroupResolver: { "TESTTEAM.Groves.Settings.Layout" })
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
		try png.write(to: URL(fileURLWithPath: "/tmp/groves-\(name).png"))
	}

	private func outline(in view: NSView) -> NSOutlineView? {
		if let outline = view as? NSOutlineView { return outline }
		return view.subviews.lazy.compactMap { outline(in: $0) }.first
	}

	private func editableFields(in view: NSView) -> [NSTextField] {
		if let field = view as? NSTextField, field.isEditable { return [field] }
		return view.subviews.flatMap { editableFields(in: $0) }
	}
}
