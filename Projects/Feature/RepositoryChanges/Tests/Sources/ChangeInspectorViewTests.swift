import AppKit
import SwiftUI
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct ChangeInspectorViewTests {
	@Test
	func refreshingStatisticsKeepsTheFileDetailsAndScrollPosition() async throws {
		let controller = NSHostingController(rootView: inspector(isLoading: false))
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless],
			backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
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
			try await Task.sleep(for: .milliseconds(10))
		}
		let original = try #require(scrollView(in: controller.view))
		#expect((original.documentView?.frame.height ?? 0) > original.contentView.bounds.height + 40)
		original.contentView.scroll(to: NSPoint(x: 0, y: 40))
		original.reflectScrolledClipView(original.contentView)
		let offset = original.contentView.bounds.origin.y
		for isLoading in [true, false, true, false] {
			controller.rootView = inspector(isLoading: isLoading)
			for _ in 0..<3 {
				controller.view.layoutSubtreeIfNeeded()
				try await Task.sleep(for: .milliseconds(10))
			}
			let current = try #require(scrollView(in: controller.view))
			#expect(current === original)
			#expect(abs(current.contentView.bounds.origin.y - offset) < 1)
		}
	}

	private func inspector(isLoading: Bool) -> some View {
		ChangeInspectorView(
			fileName: "RepositoryWorkspaceAssembly.swift",
			filePath: "Projects/App/Sources/Repository/DI/RepositoryWorkspaceAssembly.swift",
			fileState: .modified, isStaged: true, selectedCount: 1,
			additionCount: 8, deletionCount: 3, isLoading: isLoading
		).frame(width: 300, height: 200)
	}

	private func scrollView(in view: NSView) -> NSScrollView? {
		if let scrollView = view as? NSScrollView { return scrollView }
		return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
	}
}
