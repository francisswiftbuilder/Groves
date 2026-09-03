import AppKit
import SwiftUI

@MainActor
final class NativeWindowTabCoordinator {
	static let shared = NativeWindowTabCoordinator()

	private let registeredWindows = NSHashTable<NSWindow>.weakObjects()

	private init() {}

	func register(_ window: NSWindow) {
		guard registeredWindows.contains(window) == false else { return }

		window.tabbingIdentifier = "com.francisswiftbuilder.Groves.Repository"
		window.tabbingMode = .preferred
		if window.tabGroup?.isTabBarVisible == false {
			window.toggleTabBar(nil)
		}

		let anchorWindow =
			NSApp.keyWindow.flatMap { registeredWindows.contains($0) ? $0 : nil }
			?? registeredWindows.allObjects.first
		registeredWindows.add(window)

		guard let anchorWindow, anchorWindow !== window else { return }
		if anchorWindow.tabGroup !== window.tabGroup {
			anchorWindow.addTabbedWindow(window, ordered: .above)
		}
		window.makeKeyAndOrderFront(nil)
	}
}
