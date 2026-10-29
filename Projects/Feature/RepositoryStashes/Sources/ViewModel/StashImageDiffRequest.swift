import CoreRepositoryDiff
import Foundation

struct StashImageDiffRequest: Hashable {
	let id: Int
	let repositoryURL: URL
	let stashHash: String
	let fileID: CommitDiffFile.ID
}
