import Foundation

@MainActor
protocol AskPassParentMonitoring {
	func startMonitoring(parentProcessIdentifier: Int32, onParentExit: @escaping () -> Void)
	func stopMonitoring()
}
