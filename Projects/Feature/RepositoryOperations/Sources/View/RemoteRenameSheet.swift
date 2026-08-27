import DomainGitInterface
import SwiftUI

struct RemoteRenameSheet: View {
	@Environment(\.dismiss) private var dismiss
	let remote: GitRemote
	let onRename: (String) -> Void
	@State private var name: String

	init(remote: GitRemote, onRename: @escaping (String) -> Void) {
		self.remote = remote
		self.onRename = onRename
		_name = State(initialValue: remote.name)
	}

	var body: some View {
		Form {
			TextField("Remote Name", text: $name)
		}
		.padding(20)
		.frame(width: 380, height: 130)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Rename") { onRename(name) }
					.buttonStyle(.borderedProminent)
					.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
	}
}
