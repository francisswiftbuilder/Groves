import AppKit
import SwiftUI

struct NativeWindowTabConfigurator: NSViewRepresentable {
	@Environment(\.windowTabCoordinator) private var coordinator

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> WindowObservationView {
		let view = WindowObservationView()
		view.didMoveToWindow = { window in
			context.coordinator.register(window, using: coordinator)
		}
		return view
	}

	func updateNSView(_ nsView: WindowObservationView, context: Context) {
		context.coordinator.register(nsView.window, using: coordinator)
	}

	@MainActor
	final class Coordinator {
		private weak var window: NSWindow?

		func register(
			_ window: NSWindow?,
			using coordinator: (any RepositoryWindowTabCoordinating)?
		) {
			guard let window, self.window !== window else { return }
			self.window = window
			coordinator?.configure(window)
			Task { @MainActor [weak self, weak window] in
				guard let self, let window, self.window === window else { return }
				coordinator?.register(window)
			}
		}
	}
}
