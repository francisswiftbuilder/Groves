import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

struct CommitTaskEditor: View {
	let viewModel: CommitPlanViewModel

	var body: some View {
		CommitReviewContainer {
			if let unit = viewModel.selectedUnit {
				PatchReviewView(id: unit.id, path: unit.path, patch: unit.patch)
			} else {
				EmptyStateView(title: "No Change Selected", systemImage: "doc.text")
			}
		} header: {
			messageEditor
		} footer: {
			EmptyView()
		}
		.disabled(viewModel.isBusy || viewModel.needsRefresh)
	}

	private var messageEditor: some View {
		Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
			GridRow(alignment: .firstTextBaseline) {
				Text("Summary").gridColumnAlignment(.trailing)
				TextField(
					"Summary",
					text: Binding(
						get: { viewModel.selectedTask?.subject ?? "" }, set: { viewModel.didUpdateSubject($0) })
				)
				.labelsHidden()
				.textFieldStyle(.roundedBorder)
			}
			GridRow(alignment: .firstTextBaseline) {
				Text("Description")
				TextField(
					"Description",
					text: Binding(
						get: { viewModel.selectedTask?.body ?? "" }, set: { viewModel.didUpdateBody($0) }),
					prompt: Text("Optional"), axis: .vertical
				)
				.lineLimit(3...5)
				.fixedSize(horizontal: false, vertical: true)
				.textFieldStyle(.roundedBorder)
				.labelsHidden()
			}
			GridRow(alignment: .firstTextBaseline) {
				Text("Change")
				HStack(spacing: 12) {
					Picker(
						"Change",
						selection: Binding(
							get: { viewModel.selectedUnit?.id ?? "" }, set: { viewModel.selectedUnitID = $0 })
					) {
						ForEach(viewModel.selectedUnits) { unit in
							Text(unit.path + (unit.hunk.map { " · line \($0.newStartLine)" } ?? " · whole file"))
								.lineLimit(1)
								.truncationMode(.middle)
								.tag(unit.id)
						}
					}
					.labelsHidden()
					.frame(minWidth: 0, maxWidth: .infinity)
					.help(viewModel.selectedUnit?.path ?? "")
					Menu("Move to") {
						ForEach(viewModel.tasks.filter { $0.id != viewModel.selectedTaskID }) { task in
							Button(task.subject.isEmpty ? "Untitled Commit" : task.subject) {
								viewModel.didMoveSelectedUnit(to: task.id)
							}
						}
						Divider()
						Button("New Commit") { viewModel.didMoveSelectedUnit(to: nil) }
					}
					.fixedSize()
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(20)
		.background { Rectangle().fill(.background) }
	}
}
