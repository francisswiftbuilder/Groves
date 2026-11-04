import Foundation

actor CommitAnalysisCache {
	private var summaries: [String: String] = [:]
	private var keys: [String] = []

	func summary(for key: String) -> String? { summaries[key] }

	func store(_ summary: String, for key: String) {
		if summaries[key] == nil { keys.append(key) }
		summaries[key] = summary
		while keys.count > 256 {
			summaries.removeValue(forKey: keys.removeFirst())
		}
	}
}
