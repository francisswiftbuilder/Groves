import DomainGitInterface
import SwiftUI

struct CommitBar: View {
	let viewModel: CommitViewModel

	var body: some View {
		VStack(spacing: 8) {
			TextField(
				"Summary", text: Binding(get: { viewModel.subject }, set: { viewModel.subject = $0 })
			)
			.textFieldStyle(.roundedBorder)
			TextField(
				"Description (optional)",
				text: Binding(get: { viewModel.body }, set: { viewModel.body = $0 }), axis: .vertical
			)
			.textFieldStyle(.roundedBorder)
			.lineLimit(2...4)
			HStack(spacing: 12) {
				Toggle(
					"Amend Last Commit",
					isOn: Binding(
						get: { viewModel.isAmendingCommit }, set: { viewModel.didSetAmendingCommit($0) })
				)
				.toggleStyle(.checkbox)
				.disabled(!viewModel.canAmendCommit)
				Menu("Commit Options", systemImage: "ellipsis.circle") {
					Button("Amend Without Editing Message") {
						viewModel.didRequestAmendWithoutEditingMessage()
					}
					.disabled(!viewModel.hasStagedChanges || !viewModel.canAmendCommit)
				}
				.labelStyle(.iconOnly)
				.menuStyle(.borderlessButton)
				.menuIndicator(.hidden)
				.fixedSize()
				Spacer()
				if let planningViewModel = viewModel.planningViewModel {
					CommitPlanButton(
						viewModel: planningViewModel,
						isEnabled: !viewModel.isLoading && !viewModel.isAmendingCommit)
				}
				Button(viewModel.isAmendingCommit ? "Amend" : "Commit") {
					viewModel.didRequestCommit()
				}
				.buttonStyle(.borderedProminent)
				.keyboardShortcut(.return, modifiers: [.command])
				.disabled(!viewModel.canCommit)
			}
		}
		.padding(12)
		.background(.bar)
	}
}
