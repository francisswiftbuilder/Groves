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
		}
	}
}
