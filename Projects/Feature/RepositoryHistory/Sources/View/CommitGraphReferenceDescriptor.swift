import SwiftUI

struct CommitGraphReferenceDescriptor: Identifiable, Hashable {
	enum Kind: Int, Hashable {
		case currentBranch
		case localBranch
		case tag
		case remoteBranch
		case detachedHead
	}

	let kind: Kind
	let name: String
	let rawValue: String

	var id: String {
		"\(kind.rawValue):\(name)"
	}

	var systemImage: String {
		switch kind {
		case .currentBranch:
			"checkmark"
		case .localBranch:
			"arrow.triangle.branch"
		case .tag:
			"tag"
		case .remoteBranch:
			"cloud"
		case .detachedHead:
			"scope"
		}
	}

	var iconColor: Color {
		switch kind {
		case .currentBranch:
			Color(nsColor: .controlAccentColor)
		case .localBranch, .detachedHead:
			Color(nsColor: .secondaryLabelColor)
		case .tag:
			.orange
		case .remoteBranch:
			.blue
		}
	}

	var textColor: Color {
		switch kind {
		case .remoteBranch:
			Color(nsColor: .secondaryLabelColor)
		case .currentBranch, .localBranch, .tag, .detachedHead:
			Color(nsColor: .labelColor)
		}
	}

	var fontWeight: Font.Weight {
		kind == .currentBranch ? .semibold : .medium
	}

	var accessibilityLabel: String {
		switch kind {
		case .currentBranch:
			"Current branch, \(name)"
		case .localBranch:
			"Local branch, \(name)"
		case .tag:
			"Tag, \(name)"
		case .remoteBranch:
			"Remote branch, \(name)"
		case .detachedHead:
			"Detached HEAD"
		}
	}

	var helpText: String {
		rawValue == name ? accessibilityLabel : "\(accessibilityLabel) · \(rawValue)"
	}

	static func descriptors(
		for references: [String],
		remoteNames: Set<String>
	) -> [Self] {
		var seenIDs = Set<String>()
		return
			references
			.map { Self(reference: $0, remoteNames: remoteNames) }
			.sorted(by: compare)
			.filter { seenIDs.insert($0.id).inserted }
	}

	private init(reference: String, remoteNames: Set<String>) {
		rawValue = reference
		if let name = reference.removingPrefix("HEAD -> ") {
			kind = .currentBranch
			self.name = name
		} else if let name = reference.removingPrefix("tag: ") {
			kind = .tag
			self.name = name.removingPrefix("refs/tags/") ?? name
		} else if reference == "HEAD" {
			kind = .detachedHead
			name = "HEAD"
		} else if let name = Self.remoteReferenceName(reference, remoteNames: remoteNames) {
			kind = .remoteBranch
			self.name = name
		} else {
			kind = .localBranch
			name = reference.removingPrefix("refs/heads/") ?? reference
		}
	}

	private static func compare(lhs: Self, rhs: Self) -> Bool {
		if lhs.kind.rawValue != rhs.kind.rawValue {
			return lhs.kind.rawValue < rhs.kind.rawValue
		}
		return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
	}

	private static func remoteReferenceName(
		_ reference: String,
		remoteNames: Set<String>
	) -> String? {
		let target = reference.components(separatedBy: " -> ").last ?? reference
		let fullName = target.removingPrefix("refs/remotes/") ?? target
		guard remoteNames.contains(where: { fullName.hasPrefix("\($0)/") }) else {
			return nil
		}
		return fullName
	}
}
