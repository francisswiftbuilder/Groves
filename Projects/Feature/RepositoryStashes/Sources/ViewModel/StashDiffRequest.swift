import Foundation

struct StashDiffRequest: Hashable {
	let id: Int
	let repositoryURL: URL
	let stashID: String
}
