import SwiftUI

extension View {
	func welcomeCard() -> some View {
		padding(16)
			.frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
			.background(.regularMaterial, in: .rect(cornerRadius: 12))
			.overlay {
				RoundedRectangle(cornerRadius: 12)
					.stroke(.quaternary, lineWidth: 1)
			}
	}
}
