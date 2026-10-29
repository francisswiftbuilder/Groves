import AppKit
import DomainGitInterface
import SwiftUI
import Testing

@testable import Groves

@Suite(.serialized)
@MainActor
struct NativeWindowTabCoordinatorTests {
	private struct CoordinatorProbe: View {
		@Environment(\.windowTabCoordinator) private var coordinator
		let didResolve: @MainActor ((any RepositoryWindowTabCoordinating)?) -> Void

		var body: some View {
			Color.clear.onAppear { didResolve(coordinator) }
		}
	}

	@Test
	func testClosingWindowWithExistingControllerRemovesSavedRepository() {
		let repository = makeRepository()
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let coordinator = makeCoordinator(viewModel: viewModel)
		let window = makeWindow()
		let existingController = NSWindowController(window: window)
		window.windowController = existingController
		coordinator.register(window, repositoryID: repository.id)

		#expect(window.windowController === existingController)
		window.close()

		#expect(store.removedRepositoryIDs == [repository.id])
		#expect(viewModel.tabs.isEmpty)
	}

	@Test
	func testTerminationPreservesRepositoriesAndSelection() {
		let first = makeRepository(position: 0)
		let second = makeRepository(position: 1)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let coordinator = makeCoordinator(viewModel: viewModel)
		let firstWindow = makeWindow()
		let secondWindow = makeWindow()
		coordinator.register(firstWindow, repositoryID: first.id)
		coordinator.register(secondWindow, repositoryID: second.id)
		viewModel.didSelectTab(first.id)
		coordinator.prepareForTermination()

		firstWindow.close()
		secondWindow.close()

		let restored = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		#expect(restored.tabs.map(\.id) == [first.id, second.id])
		#expect(restored.selectedTabID == first.id)
		#expect(store.removedRepositoryIDs.isEmpty)
	}

	@Test
	func testClosingDuplicateWindowPreservesRepositoryUntilLastWindowCloses() {
		let repository = makeRepository()
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let coordinator = makeCoordinator(
			viewModel: makeRepositoryTabsViewModel(savedRepositoryStore: store)
		)
		let firstWindow = makeWindow()
		let secondWindow = makeWindow()
		coordinator.register(firstWindow, repositoryID: repository.id)
		coordinator.register(secondWindow, repositoryID: repository.id)

		firstWindow.close()

		#expect(store.removedRepositoryIDs.isEmpty)
		#expect(store.repositories.map(\.id) == [repository.id])

		secondWindow.close()

		#expect(store.removedRepositoryIDs == [repository.id])
	}

	@Test
	func testNativeWindowSelectionPersistsRepository() {
		let first = makeRepository(position: 0)
		let second = makeRepository(position: 1)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let coordinator = makeCoordinator(viewModel: viewModel)
		let firstWindow = makeWindow()
		let secondWindow = makeWindow()
		defer {
			coordinator.prepareForTermination()
			firstWindow.close()
			secondWindow.close()
		}
		coordinator.register(firstWindow, repositoryID: first.id)
		coordinator.register(secondWindow, repositoryID: second.id)

		NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: firstWindow)

		#expect(viewModel.selectedTabID == first.id)
		#expect(store.selectedRepositoryID == first.id)
	}

	@Test
	func testRestorationWaitsForPrimaryWindowAndPreservesSelectedRepository() throws {
		let first = makeRepository(position: 0, isSelected: false)
		let selected = makeRepository(position: 1)
		let last = makeRepository(position: 2, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, selected, last])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let coordinator = makeCoordinator(viewModel: viewModel)
		let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
		defer { closeWindows(openedAfter: existingWindows, using: coordinator) }
		let primaryWindow = makeWindow()
		let restoration = try #require(viewModel.requestWindowRestoration(currentRepositoryID: nil))

		coordinator.restoreRepositoryWindows(restoration)
		coordinator.register(primaryWindow, repositoryID: selected.id)

		#expect(primaryWindow.tabGroup?.windows.count == 3)
		#expect(primaryWindow.tabGroup?.selectedWindow === primaryWindow)
		#expect(viewModel.selectedTabID == selected.id)
		#expect(store.selectionRequestIDs.isEmpty)
	}

	@Test
	func testOpeningExistingRepositoryFocusesItsWindowWithoutCreatingDuplicate() {
		let repository = makeRepository()
		let coordinator = makeCoordinator(
			viewModel: makeRepositoryTabsViewModel(
				savedRepositoryStore: SavedRepositoryStoreSpy(repositories: [repository])
			)
		)
		let window = makeWindow()
		defer {
			coordinator.prepareForTermination()
			window.close()
		}
		coordinator.register(window, repositoryID: repository.id)
		let windowCount = NSApp.windows.count

		coordinator.openNewTab(repositoryID: repository.id, from: window)

		#expect(NSApp.windows.count == windowCount)
	}

	@Test
	func testNewWindowReceivesCoordinatorAndCanOpenAnotherTabWithoutAnAnchor() async throws {
		var receivedCoordinator: (any RepositoryWindowTabCoordinating)?
		let coordinator = NativeWindowTabCoordinator(
			actions: .init(didSelectRepository: { _ in }, didCloseRepository: { _ in }),
			makeRootView: { _ in
				AnyView(
					CoordinatorProbe { coordinator in
						receivedCoordinator = coordinator
					}
				)
			}
		)
		let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
		defer { closeWindows(openedAfter: existingWindows, using: coordinator) }

		coordinator.openNewTab(repositoryID: UUID(), from: nil)
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(3))
		while receivedCoordinator == nil, clock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		let injectedCoordinator = try #require(receivedCoordinator)

		#expect(injectedCoordinator === coordinator)
		injectedCoordinator.openNewTab(repositoryID: UUID(), from: nil)
		let openedWindows = NSApp.windows.filter { !existingWindows.contains(ObjectIdentifier($0)) }
		#expect(openedWindows.count == 2)
	}

	@Test
	func testDelayedRegistrationDoesNotReactivateClosedWindow() {
		let repositoryID = UUID()
		var selectedIDs: [UUID] = []
		var closedIDs: [UUID] = []
		let coordinator = NativeWindowTabCoordinator(
			actions: .init(
				didSelectRepository: { selectedIDs.append($0) },
				didCloseRepository: { closedIDs.append($0) }
			),
			makeRootView: { _ in AnyView(EmptyView()) }
		)
		let window = makeWindow()
		coordinator.register(window, repositoryID: repositoryID)
		window.close()
		let selectionCount = selectedIDs.count

		coordinator.register(window, repositoryID: repositoryID)
		NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

		#expect(selectedIDs.count == selectionCount)
		#expect(closedIDs == [repositoryID])
	}

	private func makeCoordinator(viewModel: RepositoryTabsViewModel) -> NativeWindowTabCoordinator {
		NativeWindowTabCoordinator(
			actions: .init(
				didSelectRepository: { viewModel.didSelectTab($0) },
				didCloseRepository: { viewModel.didRequestCloseTab($0) }
			),
			makeRootView: { _ in AnyView(EmptyView()) }
		)
	}

	private func makeWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func closeWindows(
		openedAfter existingWindows: Set<ObjectIdentifier>,
		using coordinator: NativeWindowTabCoordinator
	) {
		coordinator.prepareForTermination()
		for window in NSApp.windows where !existingWindows.contains(ObjectIdentifier(window)) {
			window.close()
		}
	}

	private func makeRepository(position: Int = 0, isSelected: Bool = true) -> SavedRepository {
		SavedRepository(
			id: UUID(),
			name: "Repository\(position)",
			url: URL(fileURLWithPath: "/tmp/Repository\(position)", isDirectory: true),
			position: position,
			isSelected: isSelected
		)
	}
}
