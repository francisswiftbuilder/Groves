struct GitPushReport {
	let completed: [String]
	let rejected: [String]

	init(_ result: GitCommandResult) {
		var completed: [String] = []
		var rejected: [String] = []
		for line in result.standardOutput.split(whereSeparator: \.isNewline) {
			let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
			guard fields.count == 3, fields[0].count == 1,
				let reference = fields[1].split(separator: ":", omittingEmptySubsequences: false).last
			else { continue }
			let name =
				reference.hasPrefix("refs/tags/") ? reference.dropFirst("refs/tags/".count) : reference
			let summary = "\(name) \(fields[2])"
			if fields[0] == "!" { rejected.append(summary) } else { completed.append(summary) }
		}
		if rejected.isEmpty, let error = result.failureDescription { rejected.append(error) }
		self.completed = completed
		self.rejected = rejected
	}
}
