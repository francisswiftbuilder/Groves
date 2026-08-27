import Foundation

let status = MainActor.assumeIsolated {
	TreesAskPassApplication().run(
		arguments: Array(CommandLine.arguments.dropFirst()),
		environment: ProcessInfo.processInfo.environment
	)
}
exit(status)
