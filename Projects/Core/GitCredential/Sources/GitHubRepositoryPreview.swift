public struct GitHubRepositoryPreview: Sendable {
	public let files: [GitHubRepositoryFile]
	public let readme: String?
	public let isReadmeTruncated: Bool
}
