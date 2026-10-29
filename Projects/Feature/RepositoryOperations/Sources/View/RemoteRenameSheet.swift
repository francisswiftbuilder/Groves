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
			TextField("Remote Name", text: $name)
				.disabled(isLoading)
			if let errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.padding(20)
		.frame(width: 380, height: 220)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.disabled(isLoading)
				Button("Rename") { onRename(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
					.buttonStyle(.borderedProminent)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
		.interactiveDismissDisabled(isLoading)
	}
}
