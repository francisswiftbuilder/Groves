import SwiftUI

extension View {
	func welcomeCard() -> some View {
		padding(18)
			.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
			.background(.regularMaterial, in: .rect(cornerRadius: 14))
			.overlay {
				RoundedRectangle(cornerRadius: 14)
					.stroke(.quaternary, lineWidth: 1)
			}
	}
}
