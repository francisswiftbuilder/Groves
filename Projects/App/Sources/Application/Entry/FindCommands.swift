import AppKit
import FeatureRepositoryInterface
import SwiftUI

struct FindCommands: Commands {
	@FocusedValue(\.repositoryFindPresentation) private var repositoryFindPresentation

	var body: some Commands {
		CommandGroup(after: .textEditing) {
			Button("Find…", action: performFind)
				.keyboardShortcut("f", modifiers: .command)
		}
	}

	private func performFind() {
		if let repositoryFindPresentation {
			repositoryFindPresentation.wrappedValue = true
		} else {
			showFindInterface()
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
