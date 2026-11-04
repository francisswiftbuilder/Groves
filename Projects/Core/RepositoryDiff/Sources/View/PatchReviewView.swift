import CoreRepositoryUI
import SwiftUI

public struct PatchReviewView: View {
	@State private var viewerModel = DiffViewerViewModel()
	@State private var searchModel = RepositorySearchViewModel()
	private let id: String
	private let path: String
	private let patch: String

	public init(id: String, path: String, patch: String) {
		self.id = id
		self.path = path
		self.patch = patch
	}

	public var body: some View {
		VStack(spacing: 0) {
			if patch.contains("GIT binary patch") {
				EmptyStateView(
					title: "Binary File",
					message: "Included as a whole file.",
					systemImage: "doc")
			} else if !viewerModel.hasParsed(viewerInput) {
				LoadingStateView(title: "Loading Change")
			} else if let presentation = viewerModel.presentation, !presentation.document.lines.isEmpty {
				DiffUnifiedView(
					document: presentation.document,
					filePath: path, searchModel: searchModel, lineAction: nil, hunkActions: [],
					isApplyingAction: false, onApplyLine: { _, _ in }, onApplyHunk: { _, _ in })
			} else {
				EmptyStateView(
					title: "No Text Changes", message: "This change has no text diff to display.",
					systemImage: "doc")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.task(id: viewerInput) {
			guard !patch.contains("GIT binary patch") else { return }
			await viewerModel.update(input: viewerInput)
		}
	}

	private var viewerInput: DiffViewerViewModel.Input {
		.init(sourceID: id, filePath: path, diff: patch)
	}
}
