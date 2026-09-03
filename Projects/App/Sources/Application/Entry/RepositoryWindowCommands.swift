import AppKit
import SwiftUI

struct RepositoryWindowCommands: Commands {
	private let coordinator: any RepositoryWindowTabCoordinating

	init(coordinator: any RepositoryWindowTabCoordinating) {
		self.coordinator = coordinator
	}

	var body: some Commands {
		CommandGroup(replacing: .newItem) {
			Button("New Repository Tab") {
				coordinator.openNewTab(repositoryID: nil, from: nil)
			}
			.keyboardShortcut("t", modifiers: .command)
		}
	}
}
