import SwiftUI

struct EmptyStateView: View {
	let title: String
	let message: String
	let systemImage: String
	let actionTitle: String?
	let actionSystemImage: String?
	let action: (() -> Void)?
	init(
		title: String,
		message: String,
		systemImage: String,
		actionTitle: String? = nil,
		actionSystemImage: String? = nil,
		action: (() -> Void)? = nil
	) {
		self.title = title
		self.message = message
		self.systemImage = systemImage
		self.actionTitle = actionTitle
		self.actionSystemImage = actionSystemImage
		self.action = action
	}

	var body: some View {
		ContentUnavailableView {
			Label(title, systemImage: systemImage)
		} description: {
			Text(message)
		} actions: {
			if let actionTitle, let action {
				Button(action: action) {
					if let actionSystemImage {
						Label(actionTitle, systemImage: actionSystemImage)
					} else {
						Text(actionTitle)
					}
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.regular)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
