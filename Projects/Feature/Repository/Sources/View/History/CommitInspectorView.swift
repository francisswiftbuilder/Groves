import DomainGitInterface
import SwiftUI

struct CommitInspectorView: View {
	let commit: GitCommit?
	let files: [CommitDiffFile]
	let isLoadingFiles: Bool
	let remoteNames: Set<String>
	@Binding var selectedFileID: CommitDiffFile.ID?

	var body: some View {
		VStack(spacing: 0) {
			inspectorHeader
			Divider()
			inspectorContent
		}
	}

	private var inspectorHeader: some View {
		HStack {
			Text("Commit")
				.font(.subheadline.weight(.semibold))
			Spacer()
			if let commit {
				ShareLink(item: commit.hash) {
					Image(systemName: "square.and.arrow.up")
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.plain)
				.help("Share Commit Hash")
			}
		}
		.padding(.horizontal, 12)
		.frame(height: 44)
		.background(.bar)
	}

	@ViewBuilder
	private var inspectorContent: some View {
		if let commit {
			List(selection: $selectedFileID) {
				commitSummary(commit)
					.padding(.vertical, 8)
					.selectionDisabled()
					.listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

				commitInformation(commit)
					.padding(.vertical, 8)
					.selectionDisabled()
					.listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

				if !commit.references.isEmpty {
					commitReferences(commit)
						.padding(.vertical, 8)
						.selectionDisabled()
						.listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
				}

				changedFiles
			}
			.listStyle(.plain)
		} else {
			EmptyStateView(
				title: "No Commit Selected",
				message: "Select a commit to inspect its details.",
				systemImage: "clock"
			)
		}
	}

	private func commitSummary(_ commit: GitCommit) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(commit.subject)
				.font(.headline)
				.fixedSize(horizontal: false, vertical: true)
			if !commit.body.isEmpty {
				Text(commit.body)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private func commitInformation(_ commit: GitCommit) -> some View {
		CommitInspectorSection("Information") {
			CommitInspectorValue("Author", value: commit.author)
			CommitInspectorValue(
				"Committed",
				value: commit.date.formatted(date: .abbreviated, time: .shortened)
			)
			CommitInspectorValue("Hash", value: commit.shortHash, isMonospaced: true)
			if !commit.parentHashes.isEmpty {
				CommitInspectorValue(
					"Parents",
					value: commit.parentHashes.map { String($0.prefix(7)) }.joined(separator: ", "),
					isMonospaced: true
				)
			}
		}
	}

	@ViewBuilder
	private func commitReferences(_ commit: GitCommit) -> some View {
		if !commit.references.isEmpty {
			CommitInspectorSection("References") {
				FlowLayout(spacing: 6) {
					ForEach(references(for: commit)) { reference in
						CommitReferenceTag(descriptor: reference)
					}
				}
			}
		}
	}

	private func references(for commit: GitCommit) -> [CommitGraphReferenceDescriptor] {
		CommitGraphReferenceDescriptor.descriptors(
			for: commit.references,
			remoteNames: remoteNames
		)
	}

	private var changedFiles: some View {
		Section {
			if isLoadingFiles {
				HStack(spacing: 8) {
					ProgressView()
						.controlSize(.small)
					Text("Loading changed files…")
						.foregroundStyle(.secondary)
				}
				.font(.caption)
				.listRowSeparator(.hidden)
			} else {
				ForEach(files) { file in
					CommitChangedFileRow(file: file)
						.tag(file.id)
						.contentShape(.rect)
						.listRowInsets(.init(top: 2, leading: 16, bottom: 2, trailing: 16))
						.listRowSeparator(.hidden)
				}
			}
		} header: {
			Text("Files")
				.font(.subheadline.weight(.semibold))
				.textCase(nil)
				.foregroundStyle(.primary)
		}
	}
}
