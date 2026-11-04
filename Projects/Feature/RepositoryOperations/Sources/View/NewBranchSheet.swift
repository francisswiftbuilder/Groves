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
			} footer: {
				Text(
					"Starts at \(startCommit?.shortHash ?? "HEAD") and checks out the new branch."
				)
				.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text("New Branch")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel, action: onCancel)
					.keyboardShortcut(.cancelAction)
					.disabled(isLoading)
				Button("Create", action: onCreate)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(20)
		}
		.frame(width: 440, height: 240)
		.interactiveDismissDisabled(isLoading)
	}
}
