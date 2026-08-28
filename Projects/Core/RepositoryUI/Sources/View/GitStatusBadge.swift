import DomainGitInterface
import SwiftUI

public struct GitStatusBadge: View {
	let state: GitFileState

	public init(state: GitFileState) {
		self.state = state
	}

	public var body: some View {
		Text(state.symbol)
			.font(.system(.caption2, design: .rounded, weight: .bold))
			.foregroundStyle(color)
			.frame(width: 20, height: 20)
			.background {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(color.opacity(0.12))
			}
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
