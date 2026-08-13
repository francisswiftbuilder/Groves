import AppKit
import SwiftUI

@main
struct TreesApp: App {
	var body: some Scene {
		WindowGroup {
			AppDIContainer.shared.makeRepositoryRootView()
				.frame(minWidth: 760, minHeight: 520)
		}
		.defaultSize(width: 1_280, height: 800)
		.windowResizability(.contentMinSize)
		.windowStyle(.titleBar)
		.windowToolbarStyle(.unified)
		.commands {
			SidebarCommands()
			ToolbarCommands()
			FindCommands()
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
