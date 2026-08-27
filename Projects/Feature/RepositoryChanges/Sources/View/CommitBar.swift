import DomainGitInterface
import SwiftUI

struct CommitBar: View {
	@ObservedObject var viewModel: CommitViewModel

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
				Image(systemName: "text.bubble")
					.foregroundStyle(.secondary)
					.accessibilityHidden(true)
				TextField(
					"Summary",
					text: Binding(
						get: { viewModel.subject },
						set: { viewModel.subject = $0 }
					)
				)
				.textFieldStyle(.roundedBorder)
				Toggle(
					"Amend",
					isOn: Binding(
						get: { viewModel.isAmendingCommit },
						set: { viewModel.didSetAmendingCommit($0) }
					)
				)
				.toggleStyle(.checkbox)
				.controlSize(.small)
				.disabled(!viewModel.canAmendCommit)
				Button("Amend Without Editing Message") {
					viewModel.didRequestAmendWithoutEditingMessage()
				}
				.controlSize(.small)
				.disabled(
					!viewModel.hasStagedChanges || !viewModel.canAmendCommit
				)
				Button(viewModel.isAmendingCommit ? "Amend" : "Commit") {
					viewModel.didRequestCommit()
				}
				.buttonStyle(.borderedProminent)
				.keyboardShortcut(.return, modifiers: [.command])
				.disabled(!viewModel.canCommit)
			}
			TextField(
				"Description (optional)",
				text: Binding(
					get: { viewModel.body },
					set: { viewModel.body = $0 }
				),
				axis: .vertical
			)
			.textFieldStyle(.roundedBorder)
			.lineLimit(2...5)
			.padding(.leading, 28)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
