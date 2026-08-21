import AppKit
import SwiftUI

struct NativeWindowTabConfigurator: NSViewRepresentable {
	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> WindowObservationView {
		let view = WindowObservationView()
		view.didMoveToWindow = { window in
			context.coordinator.register(window)
		}
		return view
	}

	func updateNSView(_ nsView: WindowObservationView, context: Context) {
		context.coordinator.register(nsView.window)
	}

	@MainActor
	final class Coordinator {
		private weak var window: NSWindow?

		func register(_ window: NSWindow?) {
			guard let window, self.window !== window else { return }
			self.window = window
			Task { @MainActor [weak self, weak window] in
				guard let self, let window, self.window === window else { return }
				NativeWindowTabCoordinator.shared.register(window)
			}
		}
	}
}

final class WindowObservationView: NSView {
	var didMoveToWindow: (NSWindow?) -> Void = { _ in }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		didMoveToWindow(window)
	}
}

@MainActor
private final class NativeWindowTabCoordinator {
	static let shared = NativeWindowTabCoordinator()

	private let registeredWindows = NSHashTable<NSWindow>.weakObjects()

	private init() {}

	func register(_ window: NSWindow) {
		guard registeredWindows.contains(window) == false else { return }

		window.tabbingIdentifier = "com.francisswiftbuilder.Trees.Repository"
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
