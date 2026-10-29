import DomainGitInterface
import SwiftUI

struct NewTagSheet: View {
	let commit: GitCommit
	@Binding var name: String
	@Binding var message: String
	let isLoading: Bool
	let errorMessage: String?
	let onCancel: () -> Void
	let onCreate: () -> Void

	init(
		commit: GitCommit,
		name: Binding<String>,
		message: Binding<String>,
		isLoading: Bool = false,
		errorMessage: String? = nil,
		onCancel: @escaping () -> Void,
		onCreate: @escaping () -> Void
	) {
		self.commit = commit
		_name = name
		_message = message
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.onCancel = onCancel
		self.onCreate = onCreate
	}

	var body: some View {
		Form {
			Section("Create Tag at \(commit.shortHash)") {
				TextField("Tag name", text: $name)
					.textFieldStyle(.roundedBorder)
				TextField("Message (optional)", text: $message, axis: .vertical)
					.textFieldStyle(.roundedBorder)
					.lineLimit(2...4)
				if let errorMessage {
					Label(errorMessage, systemImage: "exclamationmark.triangle")
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
		}
		.disabled(isLoading)
		.formStyle(.grouped)
		.frame(width: 440, height: 300)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel, action: onCancel)
					.disabled(isLoading)
				Button("Create", action: onCreate)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
		.interactiveDismissDisabled(isLoading)
	}
}
