import Foundation

struct RepositorySearchMatch: Hashable, Identifiable, Sendable {
	let sourceID: Int
	let location: Int
	let length: Int

	var id: String {
		"\(sourceID):\(location):\(length)"
	}
}
