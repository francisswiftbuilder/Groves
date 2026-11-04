import DomainGitInterface
import SwiftUI

public struct GitStatusBadge: View {
	let state: GitFileState

	public init(state: GitFileState) {
		self.state = state
	}

	public var body: some View {
		Text(state.symbol)
			.font(.system(.caption, design: .monospaced, weight: .medium))
			.foregroundStyle(color)
			.frame(width: 20, height: 20)
			.accessibilityLabel(state.title)
	}

	private var color: Color {
		switch state {
		case .added, .copied, .untracked:
			return .green
		case .deleted:
			return .red
		case .modified, .renamed, .typeChanged:
			return .orange
		case .unmerged:
			return .purple
		case .ignored, .unchanged:
			return .secondary
		}
	}
}
