import DomainGitInterface
import Foundation
import SwiftUI

struct ChangesInspectorPane: View {
	private let viewModel: ChangesViewModel
	private let diffViewModel: ChangesDiffViewModel

	init(viewModel: ChangesViewModel, diffViewModel: ChangesDiffViewModel) {
		self.viewModel = viewModel
		self.diffViewModel = diffViewModel
	}

	var body: some View {
		ChangeInspectorView(
			fileName: selectedFileName,
			filePath: selectedFilePath,
			fileState: selectedFileState,
			isStaged: viewModel.selectedDiffSource == .staged,
			selectedCount: viewModel.selectedChangeIDs.count,
			diff: diffViewModel.diff,
			isLoading: diffViewModel.isLoading
		)
	}

	private var selectedFileName: String? {
		selectedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent }
	}

	private var selectedFilePath: String? {
		viewModel.selectedConflict?.path
			?? viewModel.selectedChange?.path
			?? viewModel.selectedAmendChange?.path
	}

	private var selectedFileState: GitFileState? {
		viewModel.selectedConflict == nil ? viewModel.selectedFileState : .unmerged
	}
}
