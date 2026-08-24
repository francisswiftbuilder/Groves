import AppKit
import SwiftUI

struct RepositoryWindowCommands: Commands {
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
