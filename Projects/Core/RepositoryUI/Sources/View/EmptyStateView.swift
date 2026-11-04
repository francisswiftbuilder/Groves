import SwiftUI

public struct EmptyStateView: View {
	let title: String
	let message: String
	let systemImage: String
	let actionTitle: String?
	let actionSystemImage: String?
	let action: (() -> Void)?
	public init(
		title: String,
		message: String = "",
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

	public var body: some View {
		VStack(spacing: 8) {
			Label(title, systemImage: systemImage)
				.font(.body.weight(.medium))
				.foregroundStyle(.secondary)
			if !message.isEmpty {
				Text(message)
					.font(.callout)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
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
		.frame(maxWidth: 360)
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
