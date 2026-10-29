import DomainGitInterface
import SwiftUI

struct NewBranchSheet: View {
	@Binding var name: String
	let startCommit: GitCommit?
	let isLoading: Bool
	let errorMessage: String?
	let onCancel: () -> Void
	let onCreate: () -> Void

	init(
		name: Binding<String>,
		startCommit: GitCommit? = nil,
		isLoading: Bool = false,
		errorMessage: String? = nil,
		onCancel: @escaping () -> Void,
		onCreate: @escaping () -> Void
	) {
		_name = name
		self.startCommit = startCommit
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.onCancel = onCancel
		self.onCreate = onCreate
	}

	var body: some View {
		Form {
			Section {
				TextField("Branch name", text: $name)
					.textFieldStyle(.roundedBorder)
					.disabled(isLoading)
				if let errorMessage {
					Label(errorMessage, systemImage: "exclamationmark.triangle")
						.font(.caption)
						.foregroundStyle(.red)
				}
			} header: {
				Text("Create Branch")
			} footer: {
				Text(
					"The new branch starts at \(startCommit?.shortHash ?? "the current HEAD") and becomes the active branch."
				)
				.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.frame(width: 420, height: 240)
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
