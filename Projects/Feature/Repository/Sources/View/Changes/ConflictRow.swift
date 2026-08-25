import DomainGitInterface
import SwiftUI

struct ConflictRow: View {
	let conflict: GitConflict
	let onOpen: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(URL(fileURLWithPath: conflict.path).lastPathComponent).lineLimit(1)
				Text("\(conflict.path) · \(conflictTitle)")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 0)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Conflict in \(conflict.path), \(conflictTitle)")
		.onTapGesture(count: 2, perform: onOpen)
	}

	private var conflictTitle: String {
		switch conflict.kind {
		case .bothDeleted: return "Deleted on both sides"
		case .addedByUs: return "Added in current, modified incoming"
		case .deletedByThem: return "Modified in current, deleted incoming"
		case .addedByThem: return "Added incoming, modified in current"
		case .deletedByUs: return "Deleted in current, modified incoming"
		case .bothAdded: return "Added on both sides"
		case .bothModified: return "Modified on both sides"
		}
	}
}

#Preview {
	ConflictRow(
		conflict: GitConflict(
			path: "Sources/Auth/LoginClient.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		),
		onOpen: {}
	)
	.frame(width: 360)
	.padding()
}
