import AppKit
import DomainGitInterface
import SwiftUI
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct OperationSheetLayoutTests {
	@Test(
		arguments: [
			"branch", "tag", "renameBranch", "remote", "renameRemote", "reset", "deleteLocal",
			"deleteRemote",
		],
		[ColorScheme.light, .dark])
	func editableFieldsStayWithinTheSheetContent(kind: String, colorScheme: ColorScheme) async throws
	{
		let controller = NSHostingController(
			rootView: sheet(kind: kind)
				.background { Color(nsColor: .windowBackgroundColor) }
				.environment(\.colorScheme, colorScheme))
		let size = controller.view.fittingSize
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		let host = controller.view
		host.appearance = window.appearance
		for _ in 0..<10 {
			host.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(20))
		}
		let fields = editableFields(in: host)
		#expect(kind == "reset" || kind.hasPrefix("delete") || !fields.isEmpty)
		if kind.hasPrefix("delete") {
			#expect(host.bounds.width == 460)
			#expect(host.bounds.height >= 150 && host.bounds.height <= 420)
		}
		for field in fields {
			let rect = host.convert(field.bounds, from: field)
			#expect(host.bounds.insetBy(dx: 12, dy: 12).contains(rect))
			#expect(rect.minY >= 35)
			#expect(rect.maxY <= host.bounds.height - 50)
		}
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(to: URL(fileURLWithPath: "/tmp/groves-operation-\(kind)-\(colorScheme).png"))
	}

	@Test(arguments: [ColorScheme.light, .dark])
	func syncProgressStaysWithTheCancelControl(colorScheme: ColorScheme) async throws {
		let gate = OperationsMutationGate()
		let snapshot = RepositorySnapshot(
			changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
			operationState: .normal, tags: [], stashes: [], fileTree: [])
		let model = RepositorySyncViewModel(
			dependencies: .init(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: OperationsReferencesUseCaseStub { _ in try await gate.load() },
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: { _ in }))
		defer {
			model.onDisappear()
			Task { await gate.resume(0, with: .success(snapshot)) }
		}
		model.didRequestFetchAll()
		try await gate.waitForRequests(1)
		for _ in 0..<100 {
			if model.presentedActivity != nil { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(model.presentedActivity == .fetchAll)
		let controller = NSHostingController(
			rootView: RepositorySyncCancelButton(viewModel: model)
				.labelStyle(.iconOnly)
				.padding(8)
				.background(.bar)
				.environment(\.colorScheme, colorScheme))
		let size = controller.view.fittingSize
		let window = NSWindow(
			contentRect: .init(origin: .zero, size: size), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		window.contentViewController = controller
		controller.viewWillAppear()
		controller.viewDidAppear()
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
		}
		for _ in 0..<10 {
			controller.view.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(20))
		}
		let frame = controller.view
		#expect(frame.bounds.width > frame.bounds.height)
		let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
		frame.cacheDisplay(in: frame.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(to: URL(fileURLWithPath: "/tmp/groves-sync-progress-\(colorScheme).png"))
	}

	@ViewBuilder
	private func sheet(kind: String) -> some View {
		switch kind {
		case "deleteLocal", "deleteRemote":
			BranchDeletionSheet(
				title: "Delete “feature/repository-changes”?",
				message: "The local branch will be deleted. Remote deletion affects all collaborators.",
				optionTitle:
					"Also delete remote branch “origin/feature/repository-changes-with-a-long-name”",
				unavailableReason: kind == "deleteRemote"
					? "Switch to another branch before deleting the checked-out local branch." : nil,
				onCancel: {}, onDelete: { _ in })
		case "branch":
			NewBranchSheet(name: .constant("feat/repository-changes"), onCancel: {}, onCreate: {})
		case "tag":
			NewTagSheet(
				commit: commit, name: .constant("v1.1.2"), message: .constant("Release notes"),
				onCancel: {}, onCreate: {})
		case "renameBranch":
			BranchRenameSheet(name: .constant("feat/repository-changes"), onRename: {})
		case "remote":
			RemoteEditorSheet(presentation: .add) { _, _, _ in }
		case "renameRemote":
			RemoteRenameSheet(
				remote: GitRemote(
					name: "origin", fetchURL: "https://example.com/repository.git", pushURL: nil)
			) { _ in }
		default:
			ResetCommitSheet(commit: commit, branchName: "main", mode: .constant(.mixed), onReset: {})
		}
	}

	private var commit: GitCommit {
		GitCommit(
			hash: String(repeating: "a", count: 40), shortHash: "a1b2c3d", parentHashes: [],
			author: "Developer", date: .now, references: [], subject: "Update repository views", body: "")
	}

	private func editableFields(in view: NSView) -> [NSTextField] {
		if let field = view as? NSTextField, field.isEditable { return [field] }
		return view.subviews.flatMap { editableFields(in: $0) }
	}
}
