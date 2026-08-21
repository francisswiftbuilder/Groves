import AppKit
import SwiftUI

@main
struct TreesApp: App {
	init() {
		NSWindow.allowsAutomaticWindowTabbing = true
	}

	var body: some Scene {
		WindowGroup("Trees", id: "repository", for: UUID.self) { $repositoryID in
			AppDIContainer.shared.makeRepositoryRootView(repositoryID: $repositoryID)
				.frame(minWidth: 760, minHeight: 520)
				.background {
					NativeWindowTabConfigurator()
				}
		}
		.defaultSize(width: 1_280, height: 800)
		.restorationBehavior(.disabled)
		.windowResizability(.contentMinSize)
		.windowStyle(.titleBar)
		.windowToolbarStyle(.unified)
		.commands {
			RepositoryWindowCommands()
			SidebarCommands()
			ToolbarCommands()
			FindCommands()
		}
	}
}

private struct RepositoryWindowCommands: Commands {
	@Environment(\.openWindow) private var openWindow

	var body: some Commands {
		CommandGroup(replacing: .newItem) {
			Button("New Repository Tab") {
				openWindow(id: "repository")
			}
			.keyboardShortcut("t", modifiers: .command)
		}
	}
}

private struct FindCommands: Commands {
	var body: some Commands {
		CommandGroup(after: .textEditing) {
			Button("Find…", action: showFindInterface)
				.keyboardShortcut("f", modifiers: .command)
		}
	}

	private func showFindInterface() {
		let menuItem = NSMenuItem()
		menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
		NSApp.sendAction(
			#selector(NSTextView.performFindPanelAction(_:)),
			to: nil,
			from: menuItem
		)
	}
}
