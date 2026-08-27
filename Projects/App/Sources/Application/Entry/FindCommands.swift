import AppKit
import FeatureRepositoryInterface
import SwiftUI

struct FindCommands: Commands {
	@FocusedValue(\.repositoryFindActions) private var repositoryFindActions

	var body: some Commands {
		CommandGroup(after: .textEditing) {
			Button("Find…", action: performFind)
				.keyboardShortcut("f", modifiers: .command)
			Button("Find Next", action: performFindNext)
				.keyboardShortcut("g", modifiers: .command)
			Button("Find Previous", action: performFindPrevious)
				.keyboardShortcut("g", modifiers: [.command, .shift])
		}
	}

	private func performFind() {
		if let repositoryFindActions {
			repositoryFindActions.present()
		} else {
			performTextViewFindAction(.showFindPanel)
		}
	}

	private func performFindNext() {
		if let repositoryFindActions {
			repositoryFindActions.next()
		} else {
			performTextViewFindAction(.next)
		}
	}

	private func performFindPrevious() {
		if let repositoryFindActions {
			repositoryFindActions.previous()
		} else {
			performTextViewFindAction(.previous)
		}
	}

	private func performTextViewFindAction(_ action: NSFindPanelAction) {
		let menuItem = NSMenuItem()
		menuItem.tag = Int(action.rawValue)
		NSApp.sendAction(
			#selector(NSTextView.performFindPanelAction(_:)),
			to: nil,
			from: menuItem
		)
	}
}
