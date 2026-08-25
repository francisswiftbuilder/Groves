import DomainGitInterface
import SwiftUI

struct ConflictPreview: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	let conflict: GitConflict

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Button(viewModel.oursConflictLabel) {
					viewModel.didResolveConflict(conflict, using: .ours)
				}
				Button(viewModel.theirsConflictLabel) {
					viewModel.didResolveConflict(conflict, using: .theirs)
				}
				Button("Mark Resolved") { viewModel.didMarkConflictResolved(conflict) }
				Spacer(minLength: 8)
				Button("Open in Editor", systemImage: "square.and.pencil") {
					viewModel.didOpenConflictInEditor(conflict)
				}
				.disabled(!canOpenInEditor)
				.help(canOpenInEditor ? "Open in the selected editor" : "The working file was deleted")
			}
			.padding(10)
			.background(.bar)
			Divider()
			if viewModel.isLoadingDiff {
				ProgressView("Loading conflict…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if let contents = viewModel.conflictContents {
				ScrollView([.horizontal, .vertical]) {
					Text(contents)
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(12)
				}
			} else {
				ContentUnavailableView(
					"Preview Unavailable",
					systemImage: "doc.questionmark",
					description: Text("The conflicted file is binary or was deleted.")
				)
			}
		}
	}

	private var canOpenInEditor: Bool {
		guard let repositoryURL = viewModel.repositoryURL else { return false }
		return FileManager.default.fileExists(atPath: repositoryURL.appending(path: conflict.path).path)
	}
}
