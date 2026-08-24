import AppKit
import SwiftUI

struct FindCommands: Commands {
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
