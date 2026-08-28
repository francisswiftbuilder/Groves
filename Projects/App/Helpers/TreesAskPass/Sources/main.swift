import CoreGitCredential
import Foundation

let status = MainActor.assumeIsolated {
	TreesAskPassApplication(
		makePresenter: { AppKitAskPassPromptPresenter(parentProcessIdentifier: $0) }
	).run(
		arguments: Array(CommandLine.arguments.dropFirst()),
		environment: ProcessInfo.processInfo.environment
	)
}
exit(status)
