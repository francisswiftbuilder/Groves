import DomainGitInterface
import SwiftUI

struct ResetCommitSheet: View {
	@Environment(\.dismiss) private var dismiss
	let commit: GitCommit
	@Binding var mode: GitResetMode
	let onReset: () -> Void

	init(
		commit: GitCommit,
		mode: Binding<GitResetMode>,
		onReset: @escaping () -> Void
	) {
		self.commit = commit
		_mode = mode
		self.onReset = onReset
	}

	var body: some View {
		Form {
			LabeledContent("Commit") { Text("\(commit.shortHash) · \(commit.subject)") }
			Picker("Mode", selection: $mode) {
				Text("Soft — keep index and working tree").tag(GitResetMode.soft)
				Text("Mixed — unstage changes").tag(GitResetMode.mixed)
				Text("Hard — discard tracked changes").tag(GitResetMode.hard)
			}
			.pickerStyle(.radioGroup)
		}
		.formStyle(.grouped)
		.padding(16)
		.frame(width: 480, height: 250)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Reset") { onReset() }.buttonStyle(.borderedProminent)
			}
			.padding(12)
			.background(.bar)
		}
	}
}

#Preview {
	@Previewable @State var mode = GitResetMode.mixed
	ResetCommitSheet(
		commit: GitCommit(
			hash: String(repeating: "a", count: 40),
			shortHash: "a1b2c3d",
			parentHashes: [],
			author: "Groves Developer",
			date: .now,
			references: ["HEAD -> main"],
			subject: "Improve repository operations",
			body: ""
		),
		mode: $mode,
		onReset: {}
	)
}
