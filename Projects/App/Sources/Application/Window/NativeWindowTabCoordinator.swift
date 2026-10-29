import AppKit
import SwiftUI

@MainActor
final class NativeWindowTabCoordinator: NSObject, RepositoryWindowTabCoordinating {
	struct Actions {
		let didSelectRepository: @MainActor (UUID) -> Void
		let didCloseRepository: @MainActor (UUID) -> Void
	}

	typealias RootViewFactory = @MainActor (Binding<UUID?>) -> AnyView

	private let actions: Actions
	private let makeRootView: RootViewFactory
	private let registeredWindows = NSHashTable<NSWindow>.weakObjects()
	private let closedWindows = NSHashTable<NSWindow>.weakObjects()
	private var repositoryIDs: [ObjectIdentifier: UUID] = [:]
	private var windowControllers: [RepositoryWindowController] = []
	private var pendingRestoration: RepositoryWindowRestoration?
	private var isRestoringRepositoryWindows = false
	private var isTerminating = false

	init(actions: Actions, makeRootView: @escaping RootViewFactory) {
		self.actions = actions
		self.makeRootView = makeRootView
		super.init()
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(windowDidBecomeKey),
			name: NSWindow.didBecomeKeyNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(windowWillClose),
			name: NSWindow.willCloseNotification,
			object: nil
		)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func configure(_ window: NSWindow) {
		window.tabbingIdentifier = "com.francisswiftbuilder.Groves.Repository"
		window.tabbingMode = .preferred
	}

	func register(_ window: NSWindow, repositoryID: UUID?) {
		register(window, repositoryID: repositoryID, activates: true)
	}

	func openNewTab(
		repositoryID: UUID? = nil,
		from existingWindow: NSWindow? = nil
	) {
		openNewTab(repositoryID: repositoryID, from: existingWindow, activates: true)
	}

	func restoreRepositoryWindows(_ restoration: RepositoryWindowRestoration) {
		pendingRestoration = restoration
		restorePendingRepositoryWindows()
	}

	func prepareForTermination() {
		isTerminating = true
	}

	private func register(_ window: NSWindow, repositoryID: UUID?, activates: Bool) {
		guard closedWindows.contains(window) == false else { return }
		repositoryIDs[ObjectIdentifier(window)] = repositoryID
		guard registeredWindows.contains(window) == false else {
			if window.isKeyWindow {
				didSelect(window)
			}
			restorePendingRepositoryWindows()
			return
		}
		configure(window)

		if window.windowController == nil {
			let controller = RepositoryWindowController(window: window, coordinator: self)
			window.windowController = controller
			windowControllers.append(controller)
		}

		let anchor = anchorWindow(excluding: window)
		registeredWindows.add(window)
		if let anchor {
			let target = anchor.tabGroup?.windows.last ?? anchor
			if anchor.tabGroup == nil || anchor.tabGroup !== window.tabGroup {
				target.addTabbedWindow(window, ordered: .above)
			}
			if let tabGroup = anchor.tabGroup, tabGroup.isTabBarVisible == false {
				anchor.toggleTabBar(nil)
			}
			if activates {
				select(window)
			}
		} else if window.isKeyWindow {
			didSelect(window)
		}
		restorePendingRepositoryWindows()
	}

	private func openNewTab(repositoryID: UUID?, from existingWindow: NSWindow?, activates: Bool) {
		if let repositoryID, let window = window(for: repositoryID) {
			if activates {
				select(window)
			}
			return
		}
		let anchor =
			existingWindow.flatMap {
				registeredWindows.contains($0) ? $0 : nil
			} ?? anchorWindow()
		let newWindow = NSWindow(
			contentRect: anchor?.frame ?? NSRect(x: 0, y: 0, width: 1_280, height: 800),
			styleMask: anchor?.styleMask ?? [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		configure(newWindow)
		newWindow.title = "Groves"
		newWindow.minSize = NSSize(width: 760, height: 520)
		newWindow.isReleasedWhenClosed = false
		if anchor == nil {
			newWindow.center()
		}
		newWindow.contentViewController = NSHostingController(
			rootView: HostedRepositoryRootView(
				initialRepositoryID: repositoryID,
				makeRootView: makeRootView
			)
			.environment(\.windowTabCoordinator, self)
		)
		let controller = RepositoryWindowController(window: newWindow, coordinator: self)
		newWindow.windowController = controller
		windowControllers.append(controller)
		register(newWindow, repositoryID: repositoryID, activates: activates)
		if activates {
			select(newWindow)
		}
	}

	private func restorePendingRepositoryWindows() {
		guard let restoration = pendingRestoration else { return }
		guard let primaryID = restoration.primaryRepositoryID else {
			pendingRestoration = nil
			return
		}
		guard let primaryWindow = window(for: primaryID) else { return }
		pendingRestoration = nil
		isRestoringRepositoryWindows = true
		for id in restoration.additionalRepositoryIDs {
			openNewTab(repositoryID: id, from: primaryWindow, activates: false)
		}
		primaryWindow.tabGroup?.selectedWindow = primaryWindow
		primaryWindow.makeKeyAndOrderFront(nil)
		isRestoringRepositoryWindows = false
		didSelect(primaryWindow)
	}

	private func select(_ window: NSWindow) {
		window.tabGroup?.selectedWindow = window
		window.makeKeyAndOrderFront(nil)
		didSelect(window)
	}

	private func didSelect(_ window: NSWindow) {
		guard !isRestoringRepositoryWindows, !isTerminating,
			let id = repositoryIDs[ObjectIdentifier(window)]
		else { return }
		actions.didSelectRepository(id)
	}

	@objc private func windowDidBecomeKey(_ notification: Notification) {
		guard let window = notification.object as? NSWindow,
			registeredWindows.contains(window)
		else { return }
		didSelect(window)
	}

	@objc private func windowWillClose(_ notification: Notification) {
		guard let window = notification.object as? NSWindow,
			registeredWindows.contains(window)
		else { return }
		let id = repositoryIDs.removeValue(forKey: ObjectIdentifier(window))
		closedWindows.add(window)
		registeredWindows.remove(window)
		windowControllers.removeAll { $0.window === window }
		guard !isTerminating, let id, self.window(for: id) == nil else { return }
		actions.didCloseRepository(id)
	}

	private func window(for repositoryID: UUID) -> NSWindow? {
		registeredWindows.allObjects.first {
			repositoryIDs[ObjectIdentifier($0)] == repositoryID
		}
	}

	private func anchorWindow(excluding window: NSWindow? = nil) -> NSWindow? {
		NSApp.keyWindow.flatMap {
			$0 !== window && registeredWindows.contains($0) ? $0 : nil
		} ?? registeredWindows.allObjects.first { $0 !== window }
	}
}
