struct GitFetchRefspec: Sendable {
	let value: String
	private let source: String
	let destination: String?
	private let isNegative: Bool

	private init(_ value: Substring) {
		self.value = String(value)
		isNegative = value.hasPrefix("^")
		let spec = value.dropFirst(value.hasPrefix("^") || value.hasPrefix("+") ? 1 : 0)
		let fields = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
		source = fields.first.map(String.init) ?? ""
		destination = !isNegative && fields.count == 2 && !fields[1].isEmpty ? String(fields[1]) : nil
	}

	static func parseConfiguration(_ output: String) -> [String: [Self]] {
		var result: [String: [Self]] = [:]
		for record in output.split(separator: "\0") {
			guard let newline = record.firstIndex(of: "\n") else { continue }
			let key = record[..<newline]
			guard key.hasPrefix("remote."), key.hasSuffix(".fetch") else { continue }
			let name = String(key.dropFirst("remote.".count).dropLast(".fetch".count))
			result[name, default: []].append(Self(record[record.index(after: newline)...]))
		}
		return result
	}

	static func sourceBranch(
		for trackingReference: String, in refspecs: [String: [Self]]
	) -> (remote: String, reference: String)? {
		var result: (remote: String, reference: String)?
		for (remote, mappings) in refspecs {
			for mapping in mappings {
				guard let source = mapping.sourceReference(for: trackingReference),
					!mappings.contains(where: { $0.excludes(source) })
				else { continue }
				if let result, result.remote != remote || result.reference != source { return nil }
				result = (remote, source)
			}
		}
		guard let result, result.reference.hasPrefix("refs/heads/") else { return nil }
		return result
	}

	private func sourceReference(for trackingReference: String) -> String? {
		guard let destination, let match = Self.wildcardMatch(destination, reference: trackingReference)
		else { return nil }
		guard let wildcard = source.firstIndex(of: "*") else { return source }
		return source[..<wildcard] + match + source[source.index(after: wildcard)...]
	}

	private func excludes(_ reference: String) -> Bool {
		isNegative && Self.wildcardMatch(source, reference: reference) != nil
	}

	private static func wildcardMatch(_ pattern: String, reference: String) -> String? {
		let fields = pattern.utf8.split(separator: 42, maxSplits: 1, omittingEmptySubsequences: false)
		guard fields.count == 2 else { return pattern.utf8.elementsEqual(reference.utf8) ? "" : nil }
		let prefix = fields[0]
		let suffix = fields[1]
		let bytes = reference.utf8
		guard bytes.count >= prefix.count + suffix.count,
			bytes.starts(with: prefix), bytes.suffix(suffix.count).elementsEqual(suffix)
		else { return nil }
		return String(decoding: bytes.dropFirst(prefix.count).dropLast(suffix.count), as: UTF8.self)
	}
}
