import DomainGitInterface
import SwiftUI

struct RemoteRenameSheet: View {
	@Environment(\.dismiss) private var dismiss
	let remote: GitRemote
	let isLoading: Bool
	let errorMessage: String?
	let onRename: (String) -> Void
	@State private var name: String

	init(
		remote: GitRemote, isLoading: Bool = false, errorMessage: String? = nil,
		onRename: @escaping (String) -> Void
	) {
		self.remote = remote
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.onRename = onRename
		_name = State(initialValue: remote.name)
	}

	var body: some View {
		Form {
			TextField("Name", text: $name)
				.disabled(isLoading)
			if let errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text("Rename Remote")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
					.disabled(isLoading)
				Button("Rename") { onRename(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(20)
		}
		.frame(width: 440, height: 220)
		.interactiveDismissDisabled(isLoading)
	}
}
