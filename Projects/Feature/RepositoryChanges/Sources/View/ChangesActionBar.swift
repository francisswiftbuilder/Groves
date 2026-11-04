import SwiftUI

struct ChangesActionBar: View {
	let viewModel: ChangesViewModel

	var body: some View {
		HStack(spacing: 12) {
			Text(title)
				.font(.subheadline.weight(.semibold))
				.lineLimit(1)
			Spacer(minLength: 0)
			if viewModel.isLoading { ProgressView().controlSize(.small) }
			ControlGroup {
				Button("Stage", action: viewModel.didRequestStageSelectedChanges)
					.disabled(!viewModel.canStageSelection)
					.help("Stage selected changes")
				Button("Unstage", action: viewModel.didRequestUnstageSelectedChanges)
					.disabled(!viewModel.canUnstageSelection)
					.help("Unstage selected changes")
			}
			.controlSize(.small)
			.fixedSize()
			Menu("More Staging Actions", systemImage: "ellipsis.circle") {
				Button("Stage All Changes", action: viewModel.didRequestStageAllChanges)
					.disabled(!viewModel.canStageAllChanges)
				Button("Unstage All Changes", action: viewModel.didRequestUnstageAllChanges)
					.disabled(!viewModel.canUnstageAllChanges)
			}
			.labelStyle(.iconOnly)
			.menuStyle(.borderlessButton)
			.menuIndicator(.hidden)
			.fixedSize()
			.help("More staging actions")
		}
		.padding(.horizontal, 12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: 52)
		.background(.bar)
	}

	private var title: String {
		if viewModel.selectedChangeIDs.count > 1 {
			return "\(viewModel.selectedChangeIDs.count) Changes Selected"
		}
		if viewModel.selectedConflict != nil { return "Conflict" }
		if viewModel.selectedAmendChange != nil { return "Amended Commit" }
		switch viewModel.selectedDiffSource {
		case .staged: return "Staged Changes"
		case .unstaged: return "Unstaged Changes"
		case .none: return "Working Tree"
		}
	}
}
