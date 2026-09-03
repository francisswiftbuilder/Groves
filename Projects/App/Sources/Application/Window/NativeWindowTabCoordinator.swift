import AppKit
import SwiftUI

@MainActor
final class NativeWindowTabCoordinator: RepositoryWindowTabCoordinating {
	typealias RootViewFactory = @MainActor (Binding<UUID?>) -> AnyView

	private let makeRootView: RootViewFactory
	private let registeredWindows = NSHashTable<NSWindow>.weakObjects()
	private var windowControllers: [RepositoryWindowController] = []
	var openFallback: (@MainActor (UUID?) -> Void)?

	init(makeRootView: @escaping RootViewFactory) {
		self.makeRootView = makeRootView
	}

	func configure(_ window: NSWindow) {
		window.tabbingIdentifier = "com.francisswiftbuilder.Groves.Repository"
		window.tabbingMode = .preferred
	}

	func register(_ window: NSWindow) {
		guard registeredWindows.contains(window) == false else { return }
		configure(window)

		if window.windowController == nil {
			let controller = RepositoryWindowController(
				window: window,
				coordinator: self,
				onWindowWillClose: { [weak self] controller in
					self?.didClose(controller: controller)
				}
			)
			window.windowController = controller
			windowControllers.append(controller)
		}

		let anchorWindow = anchorWindow(for: window)
		registeredWindows.add(window)

		guard let anchorWindow, anchorWindow !== window else { return }
		let targetWindow = anchorWindow.tabGroup?.windows.last ?? anchorWindow
		if anchorWindow.tabGroup == nil || anchorWindow.tabGroup !== window.tabGroup {
			targetWindow.addTabbedWindow(window, ordered: .above)
		}
		if let tabGroup = anchorWindow.tabGroup, tabGroup.isTabBarVisible == false {
			anchorWindow.toggleTabBar(nil)
		}
		anchorWindow.tabGroup?.selectedWindow = window
		window.makeKeyAndOrderFront(nil)
	}

	func openNewTab(
		repositoryID: UUID? = nil,
		from existingWindow: NSWindow? = nil
	) {
		let anchor =
			existingWindow
			?? NSApp.keyWindow
			?? registeredWindows.allObjects.first

		guard let anchor else {
			openFallback?(repositoryID)
			return
		}

		configure(anchor)

		let newWindow = NSWindow(
			contentRect: anchor.frame,
			styleMask: anchor.styleMask,
			backing: .buffered,
			defer: false
		)
		configure(newWindow)
		newWindow.title = "Groves"
		newWindow.minSize = NSSize(width: 760, height: 520)
		newWindow.isReleasedWhenClosed = false

		let hostingController = NSHostingController(
			rootView: HostedRepositoryRootView(
				initialRepositoryID: repositoryID,
				makeRootView: makeRootView
			)
		)
		newWindow.contentViewController = hostingController

		let controller = RepositoryWindowController(
			window: newWindow,
			coordinator: self,
			onWindowWillClose: { [weak self] controller in
				self?.didClose(controller: controller)
			}
		)
		newWindow.delegate = controller
		windowControllers.append(controller)
		registeredWindows.add(newWindow)

		let targetWindow = anchor.tabGroup?.windows.last ?? anchor
		targetWindow.addTabbedWindow(newWindow, ordered: .above)
		if let tabGroup = anchor.tabGroup, tabGroup.isTabBarVisible == false {
			anchor.toggleTabBar(nil)
		}
		anchor.tabGroup?.selectedWindow = newWindow
		newWindow.makeKeyAndOrderFront(nil)
	}

	private func didClose(controller: RepositoryWindowController) {
		windowControllers.removeAll { $0 === controller }
	}

	private func anchorWindow(for window: NSWindow) -> NSWindow? {
		NSApp.keyWindow.flatMap {
			$0 !== window && registeredWindows.contains($0) ? $0 : nil
		} ?? registeredWindows.allObjects.first { $0 !== window }
	}
}
