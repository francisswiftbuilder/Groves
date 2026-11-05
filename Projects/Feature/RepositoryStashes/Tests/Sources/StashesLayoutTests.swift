import AppKit
import CoreRepositoryDiff
import DomainGitInterface
import SwiftUI
import Testing

@testable import FeatureRepositoryStashes

@MainActor
struct StashesLayoutTests {
	@Test(arguments: [540.0, 980.0, 1400.0], [ColorScheme.light, .dark])
	func selectedStashUsesTwoPanesAboveTheActionBar(width: Double, colorScheme: ColorScheme)
		async throws
	{
		let stashes = (0..<2).map {
			GitStash(
				reference: "stash@{\($0)}", hash: "stash-\($0)", subject: "Saved work \($0)", date: nil)
		}
		let preferences = WorkspaceDiffPreferences()
		let model = StashesViewModel(
			dependencies: .init(
				useCase: StashesUseCaseStub(diffs: [stashes[0].id: diff, stashes[1].id: diff]),
				preferences: preferences, repositoryURL: { URL(fileURLWithPath: "/tmp/StashLayout") }),
			actions: .init(didProduceSnapshot: { _ in }, didReceiveError: { _ in }))
		model.apply(
			.init(
				changes: [], amendChanges: [], commits: [], branches: [], remotes: [],
				operationState: .normal, tags: [], stashes: stashes, fileTree: []))
		for _ in 0..<100 {
			if !model.isLoadingDiff { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(model.files.count == 1)
		let controller = NSHostingController(
			rootView:
				StashesView(
					diffSearchViewModel: RepositorySearchViewModel(), stashesViewModel: model,
					diffPreferences: preferences, onDiffOptionsChanged: {}
				)
				.frame(width: width, height: 560)
				.background { Color(nsColor: .windowBackgroundColor) }
				.environment(\.colorScheme, colorScheme))
		controller.sizingOptions = []
		let window = NSWindow(
			contentRect: .init(x: 0, y: 0, width: width, height: 560),
			styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		window.contentViewController = controller
		controller.view.frame = .init(x: 0, y: 0, width: width, height: 560)
		controller.viewWillAppear()
		controller.viewDidAppear()
		defer {
			controller.viewWillDisappear()
			controller.viewDidDisappear()
			window.close()
			model.onDisappear()
		}
		for _ in 0..<25 {
			controller.view.layoutSubtreeIfNeeded()
			try await Task.sleep(for: .milliseconds(10))
		}
		let host = controller.view
		let split = try #require(descendants(in: host).compactMap { $0 as? NSSplitView }.first)
		#expect(split.arrangedSubviews.count == 2)
		let files = host.convert(split.arrangedSubviews[0].bounds, from: split.arrangedSubviews[0])
		let preview = host.convert(split.arrangedSubviews[1].bounds, from: split.arrangedSubviews[1])
		#expect(files.width >= 219)
		#expect(preview.width >= 299)
		#expect(host.bounds.insetBy(dx: -1, dy: -1).contains(files))
		#expect(host.bounds.insetBy(dx: -1, dy: -1).contains(preview))
		let messageField = try #require(
			descendants(in: host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
		let messageBounds = host.convert(messageField.bounds, from: messageField)
		#expect(!files.insetBy(dx: 1, dy: 1).intersects(messageBounds))
		#expect(!preview.insetBy(dx: 1, dy: 1).intersects(messageBounds))
		#expect(messageBounds.minY - files.maxY >= 0 && messageBounds.minY - files.maxY <= 20)
		#expect(messageBounds.minY - preview.maxY >= 0 && messageBounds.minY - preview.maxY <= 20)
		#expect(host.bounds.insetBy(dx: 10, dy: 10).contains(messageBounds))
		if let scroll = descendants(in: split.arrangedSubviews[1]).compactMap({ $0 as? NSScrollView })
			.first
		{
			scroll.contentView.scroll(to: .init(x: 0, y: 200))
			scroll.reflectScrolledClipView(scroll.contentView)
		}
		try await Task.sleep(for: .milliseconds(50))
		host.layoutSubtreeIfNeeded()
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		try png.write(
			to: URL(fileURLWithPath: "/tmp/groves-stash-detail-\(Int(width))-\(colorScheme).png"))
		model.didSelectStash(stashes[1].id)
		#expect(model.selectedStashID == stashes[1].id)
	}

	private func descendants(in view: NSView) -> [NSView] {
		[view] + view.subviews.flatMap { descendants(in: $0) }
	}

	private var diff: String {
		"diff --git a/Sources/Player.swift b/Sources/Player.swift\n--- a/Sources/Player.swift\n+++ b/Sources/Player.swift\n@@ -1,80 +1,80 @@\n"
			+ (1...80).map { "-let previousValue\($0) = \($0)\n+let currentValue\($0) = \($0 + 1)" }
			.joined(separator: "\n")
	}
}
