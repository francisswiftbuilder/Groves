import AppKit

final class PluminonAppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		AppDIContainer.shared.windowTabCoordinator.prepareForTermination()
		return .terminateNow
	}
}
