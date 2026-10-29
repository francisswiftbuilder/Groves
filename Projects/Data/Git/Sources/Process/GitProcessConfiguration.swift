import DomainGitInterface
import Foundation

public struct GitProcessConfiguration: Sendable {
	public let executableURL: URL
	public let runtimeURL: URL?
	public let askPassHelperURL: URL?
	public let globalConfigurationURL: URL?
	public let networkPolicy: GitNetworkPolicy
	public let terminationGracePeriod: TimeInterval
	public let userKnownHostsURL: URL?
	public let noticeHandler: (@Sendable (GitProcessNotice) -> Void)?

	var isolatedHomeDirectoryURL: URL? {
		globalConfigurationURL?.deletingLastPathComponent()
			.appending(path: "Home", directoryHint: .isDirectory)
	}

	public init(
		executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
		runtimeURL: URL? = nil,
		askPassHelperURL: URL? = nil,
		globalConfigurationURL: URL? = nil,
		networkPolicy: GitNetworkPolicy = GitNetworkPolicy(),
		terminationGracePeriod: TimeInterval = 2,
		userKnownHostsURL: URL? = nil,
		noticeHandler: (@Sendable (GitProcessNotice) -> Void)? = nil
	) {
		self.executableURL = executableURL
		self.runtimeURL = runtimeURL
		self.askPassHelperURL = askPassHelperURL
		self.globalConfigurationURL = globalConfigurationURL
		self.networkPolicy = networkPolicy
		self.terminationGracePeriod = terminationGracePeriod
		self.userKnownHostsURL = userKnownHostsURL
		self.noticeHandler = noticeHandler
	}
}
