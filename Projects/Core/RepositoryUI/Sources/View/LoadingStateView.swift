import SwiftUI

public struct LoadingStateView: View {
	let title: String
	public init(title: String) {
		self.title = title
	}

	public var body: some View {
		ProgressView(title)
			.controlSize(.small)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.accessibilityElement(children: .combine)
	}
}
