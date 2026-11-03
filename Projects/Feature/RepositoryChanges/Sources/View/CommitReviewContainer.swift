import SwiftUI

struct CommitReviewContainer<Content: View, Header: View, Footer: View>: View {
	private let content: Content
	private let header: Header
	private let footer: Footer

	init(
		@ViewBuilder content: () -> Content,
		@ViewBuilder header: () -> Header,
		@ViewBuilder footer: () -> Footer
	) {
		self.content = content()
		self.header = header()
		self.footer = footer()
	}

	var body: some View {
		VStack(spacing: 0) {
			content
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .top, spacing: 0) {
			header
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			footer
		}
	}
}
