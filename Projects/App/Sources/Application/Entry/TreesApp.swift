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
			RepositoryCommands()
			SidebarCommands()
			ToolbarCommands()
			FindCommands()
		}

		Settings {
			TreesSettingsView()
		}
	}
}
