import SwiftUI

struct SplitPaneRootView<Content: View>: View {
	let content: Content

	var body: some View {
		content
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}
