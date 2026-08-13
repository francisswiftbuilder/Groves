import SwiftUI

struct EmptyStateView: View {
	let title: String
	let message: String
	let systemImage: String
	let actionTitle: String?
	let actionSystemImage: String?
	let action: (() -> Void)?
	@ScaledMetric private var symbolSize: CGFloat = 36

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
		VStack(spacing: 14) {
			Image(systemName: systemImage)
				.font(.system(size: symbolSize, weight: .light))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.frame(width: symbolSize + 34, height: symbolSize + 34)
				.background {
					RoundedRectangle(cornerRadius: 18, style: .continuous)
						.fill(.quaternary)
				}
				.accessibilityHidden(true)
			Text(title)
				.font(.title3.weight(.semibold))
			Text(message)
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 360)

			if let actionTitle, let action {
				Button(action: action) {
					if let actionSystemImage {
						Label(actionTitle, systemImage: actionSystemImage)
					} else {
						Text(actionTitle)
					}
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.padding(.top, 4)
			}
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityElement(children: action == nil ? .combine : .contain)
	}
}
