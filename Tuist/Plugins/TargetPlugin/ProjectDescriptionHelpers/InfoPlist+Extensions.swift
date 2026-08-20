import ProjectDescription

extension InfoPlist {
	public mutating func add(_ value: Plist.Value, forKey key: String) {
		var merged: [String: Plist.Value]
		switch self {
		case .dictionary(let dict):
			merged = dict
			merged[key] = value
			self = .dictionary(merged)

		case .extendingDefault(let dict):
			merged = dict
			merged[key] = value
			self = .extendingDefault(with: merged)

		default:
			merged = [:]
			merged[key] = value
			self = .extendingDefault(with: merged)
		}
	}

	public mutating func merge(_ entries: [String: Plist.Value]) {
		var merged: [String: Plist.Value]
		switch self {
		case .dictionary(let dict):
			merged = dict
		case .extendingDefault(let dict):
			merged = dict
		default:
			merged = [:]
		}
		for entry in entries { merged[entry.key] = entry.value }
		self = .extendingDefault(with: merged)
	}
}
