import CoreRepositoryDiff
import Foundation

struct StashImageDiffRequest: Hashable {
	let id: Int
	let repositoryURL: URL
	let stashID: String
	let fileID: CommitDiffFile.ID
}
