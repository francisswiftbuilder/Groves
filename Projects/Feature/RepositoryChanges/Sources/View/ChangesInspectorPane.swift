import DomainGitInterface
import Foundation
import SwiftUI

struct ChangesInspectorPane: View {
	@ObservedObject private var viewModel: ChangesViewModel
	@ObservedObject private var diffViewModel: ChangesDiffViewModel

	init(viewModel: ChangesViewModel, diffViewModel: ChangesDiffViewModel) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
		_diffViewModel = ObservedObject(wrappedValue: diffViewModel)
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
