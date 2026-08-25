import DomainGitInterface
import SwiftUI

struct NewTagSheet: View {
	let commit: GitCommit
	@Binding var name: String
	@Binding var message: String
	let onCancel: () -> Void
	let onCreate: () -> Void

	var body: some View {
		Form {
			Section("Create Tag at \(commit.shortHash)") {
				TextField("Tag name", text: $name)
					.textFieldStyle(.roundedBorder)
				TextField("Message (optional)", text: $message, axis: .vertical)
					.textFieldStyle(.roundedBorder)
					.lineLimit(2...4)
			}
		}
		.formStyle(.grouped)
		.frame(width: 440, height: 220)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel, action: onCancel)
				Button("Create", action: onCreate)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
	}
}
