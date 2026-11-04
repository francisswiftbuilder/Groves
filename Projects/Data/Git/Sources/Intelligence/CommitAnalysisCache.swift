import DomainGitInterface
import Foundation

actor CommitAnalysisCache {
	private var summaries: [String: String] = [:]
	private var keys: [String] = []
	private var modelTokenOverhead: Int?
	private var groupedPlan: GitCommitPlan?

	func groups(for input: GitCommitPlanInput) -> GitCommitPlan? {
		groupedPlan?.input == input ? groupedPlan : nil
	}

	func storeGroups(_ plan: GitCommitPlan) { groupedPlan = plan }

	func tokenOverhead() -> Int? { modelTokenOverhead }
	func storeTokenOverhead(_ count: Int) { modelTokenOverhead = count }

	func summary(for key: String) -> String? { summaries[key] }

	func store(_ summary: String, for key: String) {
		if summaries[key] == nil { keys.append(key) }
		summaries[key] = summary
		while keys.count > 256 {
			summaries.removeValue(forKey: keys.removeFirst())
		}
	}
}
