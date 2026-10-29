import AppKit

final class GrovesAppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		AppDIContainer.shared.windowTabCoordinator.prepareForTermination()
		return .terminateNow
	}
}
