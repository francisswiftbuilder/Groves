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
