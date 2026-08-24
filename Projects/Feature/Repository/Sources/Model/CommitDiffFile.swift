import Foundation

struct CommitDiffFile: Identifiable, Hashable, Sendable {
	let id: String
	let path: String
	let diff: String
	let additions: Int
	let deletions: Int

	var fileName: String {
		URL(fileURLWithPath: path).lastPathComponent
	}

}
