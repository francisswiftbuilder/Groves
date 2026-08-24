import SwiftUI

struct LoadingStateView: View {
	let title: String
	let message: String

	var body: some View {
		ContentUnavailableView {
			VStack(spacing: 10) {
				ProgressView()
					.controlSize(.regular)
				Text(title)
					.font(.headline)
			}
		} description: {
			Text(message)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityElement(children: .combine)
	}
}
