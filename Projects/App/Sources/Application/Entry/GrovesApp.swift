import AppKit
import SwiftUI

@main
struct GrovesApp: App {
	init() {
		NSWindow.allowsAutomaticWindowTabbing = true
	}

	var body: some Scene {
		WindowGroup("Groves", id: "repository", for: UUID.self) { $repositoryID in
			AppDIContainer.shared.makeRepositoryRootView(repositoryID: $repositoryID)
				.frame(minWidth: 760, minHeight: 520)
				.background {
					NativeWindowTabConfigurator()
				}
				.environment(
					\.windowTabCoordinator,
					AppDIContainer.shared.windowTabCoordinator
				)
		}
		.defaultSize(width: 1_280, height: 800)
		.restorationBehavior(.disabled)
		.windowResizability(.contentMinSize)
		.windowStyle(.titleBar)
		.windowToolbarStyle(.unified)
		.commands {
			RepositoryWindowCommands(
				coordinator: AppDIContainer.shared.windowTabCoordinator
			)
			RepositoryCommands()
			SidebarCommands()
			ToolbarCommands()
			FindCommands()
		}

		Settings {
			GrovesSettingsView()
		}
	}
}
