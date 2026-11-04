import AppKit
import DomainGitInterface
import SwiftUI
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct OperationSheetLayoutTests {
	@Test(
		arguments: ["branch", "tag", "renameBranch", "remote", "renameRemote", "reset"],
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
		#expect(kind == "reset" || !fields.isEmpty)
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

	@ViewBuilder
	private func sheet(kind: String) -> some View {
		switch kind {
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
