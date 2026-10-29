import AppKit
import SwiftUI

struct NativeWindowTabConfigurator: NSViewRepresentable {
	@Environment(\.windowTabCoordinator) private var coordinator
	let repositoryID: UUID?

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> WindowObservationView {
		let view = WindowObservationView()
		view.didMoveToWindow = { window in
			context.coordinator.register(window, repositoryID: repositoryID, using: coordinator)
		}
		return view
	}

	func updateNSView(_ nsView: WindowObservationView, context: Context) {
		context.coordinator.register(nsView.window, repositoryID: repositoryID, using: coordinator)
	}

	@MainActor
	final class Coordinator {
		private weak var window: NSWindow?
		private var repositoryID: UUID?
		private var registrationTask: Task<Void, Never>?

		deinit {
			registrationTask?.cancel()
		}

		func register(
			_ window: NSWindow?,
			repositoryID: UUID?,
			using coordinator: (any RepositoryWindowTabCoordinating)?
		) {
			guard let window, let coordinator else { return }
			guard self.window !== window || self.repositoryID != repositoryID else { return }
			self.window = window
			self.repositoryID = repositoryID
			coordinator.configure(window)
			registrationTask?.cancel()
			registrationTask = Task { @MainActor [weak self, weak window] in
				guard !Task.isCancelled, let self, let window, self.window === window else { return }
				coordinator.register(window, repositoryID: repositoryID)
			}
		}
	}
}
