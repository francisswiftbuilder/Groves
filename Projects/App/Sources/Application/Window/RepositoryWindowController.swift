import AppKit

final class RepositoryWindowController: NSWindowController, NSWindowDelegate {
	private weak var coordinator: (any RepositoryWindowTabCoordinating)?

	init(
		window: NSWindow,
		coordinator: any RepositoryWindowTabCoordinating
	) {
		self.coordinator = coordinator
		super.init(window: window)
		window.delegate = self
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func newWindowForTab(_ sender: Any?) {
		coordinator?.openNewTab(repositoryID: nil, from: window)
	}
}
