import SwiftUI

struct ConflictSideBySideComparison: View {
	let currentLabel: String
	let currentContent: String?
	let incomingLabel: String
	let incomingContent: String?
	let filePath: String
	let searchText: String
	let currentUnavailableMessage: String
	let incomingUnavailableMessage: String

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(alignment: .top, spacing: 10) {
				currentSection
					.frame(minWidth: 240, maxWidth: .infinity)
				incomingSection
					.frame(minWidth: 240, maxWidth: .infinity)
			}

			VStack(alignment: .leading, spacing: 10) {
				currentSection
				incomingSection
			}
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("\(currentLabel) and \(incomingLabel) comparison")
	}

	private var currentSection: some View {
		ConflictCodeSection(
			title: currentLabel,
			content: currentContent,
			filePath: filePath,
			searchText: searchText,
			unavailableMessage: currentUnavailableMessage
		)
	}

	private var incomingSection: some View {
		ConflictCodeSection(
			title: incomingLabel,
			content: incomingContent,
			filePath: filePath,
			searchText: searchText,
			unavailableMessage: incomingUnavailableMessage
		)
	}
}
