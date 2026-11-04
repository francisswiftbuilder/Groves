import DomainGitInterface
import SwiftUI

struct ResetCommitSheet: View {
	@Environment(\.dismiss) private var dismiss
	let commit: GitCommit
	let branchName: String
	@Binding var mode: GitResetMode
	let isLoading: Bool
	let errorMessage: String?
	let onReset: () -> Void

	init(
		commit: GitCommit,
		branchName: String,
		mode: Binding<GitResetMode>,
		isLoading: Bool = false,
		errorMessage: String? = nil,
		onReset: @escaping () -> Void
	) {
		self.commit = commit
		self.branchName = branchName
		_mode = mode
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.onReset = onReset
	}

	var body: some View {
		Form {
			LabeledContent("Branch") { Text(branchName) }
			LabeledContent("Commit") { Text("\(commit.shortHash) · \(commit.subject)") }
			Picker("Mode", selection: $mode) {
				Text("Soft — keep index and working tree").tag(GitResetMode.soft)
				Text("Mixed — unstage changes").tag(GitResetMode.mixed)
				Text("Hard — discard tracked changes").tag(GitResetMode.hard)
			}
			.pickerStyle(.radioGroup)
			if let errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.disabled(isLoading)
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text("Reset Branch")
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
				Button("Reset") { onReset() }
					.buttonStyle(.borderedProminent)
					.disabled(isLoading)
			}
			.padding(20)
		}
		.frame(width: 520, height: 330)
		.interactiveDismissDisabled(isLoading)
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
		branchName: "main", mode: $mode,
		onReset: {}
	)
}
