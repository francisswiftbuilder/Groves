import AppKit
import SwiftUI

@MainActor
final class NativeWindowTabCoordinator {
	static let shared = NativeWindowTabCoordinator()

	private let registeredWindows = NSHashTable<NSWindow>.weakObjects()

	private init() {}

	func configure(_ window: NSWindow) {
		window.tabbingIdentifier = "com.francisswiftbuilder.Groves.Repository"
		window.tabbingMode = .preferred
	}

	func register(_ window: NSWindow) {
		guard registeredWindows.contains(window) == false else { return }
		configure(window)

		let anchorWindow = anchorWindow(for: window)
		registeredWindows.add(window)

		guard let anchorWindow, anchorWindow !== window else { return }
		if anchorWindow.tabGroup !== window.tabGroup {
			anchorWindow.addTabbedWindow(window, ordered: .above)
		}
		if let tabGroup = anchorWindow.tabGroup, tabGroup.isTabBarVisible == false {
			anchorWindow.toggleTabBar(nil)
		}
		anchorWindow.tabGroup?.selectedWindow = window
		window.makeKeyAndOrderFront(nil)
	}

	private func anchorWindow(for window: NSWindow) -> NSWindow? {
		NSApp.keyWindow.flatMap {
			$0 !== window && registeredWindows.contains($0) ? $0 : nil
		} ?? registeredWindows.allObjects.first { $0 !== window }
	}
}
