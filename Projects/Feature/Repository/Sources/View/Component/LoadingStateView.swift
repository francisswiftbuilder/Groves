import SwiftUI

struct LoadingStateView: View {
	let title: String
	let message: String

	var body: some View {
		VStack(spacing: 12) {
			ProgressView()
				.controlSize(.regular)
			Text(title)
				.font(.headline)
			Text(message)
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 320)
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityElement(children: .combine)
	}
}
