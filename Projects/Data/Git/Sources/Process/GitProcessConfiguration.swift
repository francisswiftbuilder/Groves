import Foundation

public struct GitProcessConfiguration: Sendable {
	public let askPassHelperURL: URL?
	public let networkPolicy: GitNetworkPolicy
	public let terminationGracePeriod: TimeInterval

	public init(
		askPassHelperURL: URL? = nil,
		networkPolicy: GitNetworkPolicy = GitNetworkPolicy(),
		terminationGracePeriod: TimeInterval = 2
	) {
		self.askPassHelperURL = askPassHelperURL
		self.networkPolicy = networkPolicy
		self.terminationGracePeriod = terminationGracePeriod
	}
}
