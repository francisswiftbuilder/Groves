import AppKit
import SwiftUI

struct RepositoryErrorAlertModifier: ViewModifier {
	@Environment(\.openSettings) private var openSettings
	@Binding var message: String?
	var title: LocalizedStringKey = "Git Error"

	func body(content: Content) -> some View {
		content
			.alert(title, isPresented: presentation, presenting: message) { message in
				Button("OK", role: .cancel) {}
					.keyboardShortcut(.defaultAction)
				Button("Copy Details") {
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(message, forType: .string)
				}
				if message.localizedCaseInsensitiveContains("settings") {
					Button("Open Settings…") { openSettings() }
				}
			} message: { message in
				Text(message)
			}
	}

	private var presentation: Binding<Bool> {
		Binding(
			get: { message != nil },
			set: { isPresented in
				if !isPresented { message = nil }
			}
		)
	}
}
