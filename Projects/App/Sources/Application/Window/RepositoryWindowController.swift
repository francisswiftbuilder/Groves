import AppKit

final class RepositoryWindowController: NSWindowController, NSWindowDelegate {
	private weak var coordinator: (any RepositoryWindowTabCoordinating)?
	private let onWindowWillClose: ((RepositoryWindowController) -> Void)?

	init(
		window: NSWindow,
		coordinator: any RepositoryWindowTabCoordinating,
		onWindowWillClose: ((RepositoryWindowController) -> Void)? = nil
	) {
		self.coordinator = coordinator
		self.onWindowWillClose = onWindowWillClose
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

	func windowWillClose(_ notification: Notification) {
		onWindowWillClose?(self)
	}
}
