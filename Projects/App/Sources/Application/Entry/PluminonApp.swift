import AppKit
import CoreGitCredential
import SwiftUI

@main
struct PluminonApp: App {
	@NSApplicationDelegateAdaptor(PluminonAppDelegate.self) private var appDelegate

	init() {
		NSWindow.allowsAutomaticWindowTabbing = true
	}

	var body: some Scene {
		WindowGroup(PluminonRuntimeConfiguration.displayName, id: "repository", for: UUID.self) {
			$repositoryID in
			AppDIContainer.shared.makeRepositoryRootView(repositoryID: $repositoryID)
				.frame(minWidth: 760, minHeight: 520)
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
			PluminonSettingsView(accountViewModel: AppDIContainer.shared.accountViewModel)
		}
		.windowResizability(.contentSize)
	}
}
