import SwiftUI

struct CommitPlanButton: View {
	@Bindable var viewModel: CommitPlanViewModel
	let isEnabled: Bool

	var body: some View {
		Button("Split Changes…", systemImage: "apple.intelligence") { viewModel.didPresent() }
			.labelStyle(.iconOnly)
			.disabled(!isEnabled || !viewModel.canGenerate)
			.help("Review staged changes as separate commits")
			.sheet(isPresented: $viewModel.isPresented) {
				CommitPlanSheet(viewModel: viewModel)
			}
	}
}
