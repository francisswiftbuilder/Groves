import SwiftUI

struct RepositorySidebar: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	let repositories: [RepositoryTab]
	let selectedRepositoryID: RepositoryTab.ID?
	let onSelectRepository: (RepositoryTab.ID) -> Void
	let onCloseRepository: (RepositoryTab.ID) -> Void
	let onAddRepository: () -> Void
	@State private var expandedRepositoryIDs: Set<RepositoryTab.ID> = []
	@State private var selectedItem: RepositorySidebarSelection?

	var body: some View {
		List(selection: $selectedItem) {
			Section {
				ForEach(repositories) { repository in
					DisclosureGroup(
						isExpanded: expansionBinding(for: repository.id)
					) {
						RepositorySectionRows(
							workspace: repository.workspace,
							repositoryID: repository.id
						)
					} label: {
						Button {
							selectRepository(repository.id)
						} label: {
							RepositoryRow(
								workspace: repository.workspace,
								repositoryName: repository.repository.name,
								isSelected: repository.id == selectedRepositoryID
							)
						}
						.buttonStyle(.plain)
						.contextMenu {
							Button(
								"Close Repository",
								systemImage: "xmark",
								role: .destructive
							) {
								closeRepository(repository.id)
							}
						}
					}
				}
			} header: {
				RepositoryListHeader(onAddRepository: onAddRepository)
			}
		}
		.listStyle(.sidebar)
		.onAppear {
			expandSelectedRepository()
			synchronizeSelection()
		}
		.onChange(of: selectedRepositoryID) { _, _ in
			expandSelectedRepository()
			synchronizeSelection()
		}
		.onChange(of: viewModel.selectedSection) { _, _ in
			synchronizeSelection()
		}
		.task(id: selectedItem) {
			try? await Task.sleep(for: .milliseconds(1))
			guard !Task.isCancelled else { return }
			didChangeSelection(selectedItem)
		}
	}

	private var modelSelection: RepositorySidebarSelection? {
		guard
			let selectedRepositoryID,
			let repository = repositories.first(where: { $0.id == selectedRepositoryID })
		else { return nil }

		return RepositorySidebarSelection(
			repositoryID: selectedRepositoryID,
			section: repository.workspace.selectedSection ?? .changes
		)
	}

	private var expansionAnimation: Animation? {
		reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)
	}

	private func expansionBinding(for repositoryID: RepositoryTab.ID) -> Binding<Bool> {
		Binding(
			get: { expandedRepositoryIDs.contains(repositoryID) },
			set: { isExpanded in
				if isExpanded {
					expandedRepositoryIDs.insert(repositoryID)
				} else {
					expandedRepositoryIDs.remove(repositoryID)
				}
			}
		)
	}

	private func selectRepository(_ repositoryID: RepositoryTab.ID) {
		expandRepository(repositoryID)
		onSelectRepository(repositoryID)
	}

	private func synchronizeSelection() {
		let modelSelection = modelSelection
		guard selectedItem != modelSelection else { return }
		selectedItem = modelSelection
	}

	private func didChangeSelection(_ selection: RepositorySidebarSelection?) {
		guard
			let selection,
			selection != modelSelection,
			let repository = repositories.first(where: { $0.id == selection.repositoryID })
		else { return }

		expandRepository(repository.id)
		repository.workspace.didSelectSection(selection.section)
		onSelectRepository(repository.id)
	}

	private func closeRepository(_ repositoryID: RepositoryTab.ID) {
		withAnimation(expansionAnimation) {
			_ = expandedRepositoryIDs.remove(repositoryID)
		}
		onCloseRepository(repositoryID)
	}

	private func expandSelectedRepository() {
		guard let selectedRepositoryID else { return }
		expandRepository(selectedRepositoryID)
	}

	private func expandRepository(_ repositoryID: RepositoryTab.ID) {
		guard !expandedRepositoryIDs.contains(repositoryID) else { return }

		withAnimation(expansionAnimation) {
			_ = expandedRepositoryIDs.insert(repositoryID)
		}
	}
}

private struct RepositorySectionRows: View {
	@ObservedObject var workspace: WorkspaceViewModel
	let repositoryID: RepositoryTab.ID

	var body: some View {
		ForEach(WorkspaceSection.allCases) { section in
			SidebarSectionRow(
				section: section,
				badgeCount: section == .changes ? workspace.changes.count : nil
			)
			.tag(
				RepositorySidebarSelection(
					repositoryID: repositoryID,
					section: section
				)
			)
		}
	}
}

private struct RepositorySidebarSelection: Hashable {
	let repositoryID: RepositoryTab.ID
	let section: WorkspaceSection
}

private struct RepositoryListHeader: View {
	let onAddRepository: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Text("Repositories")
				.font(.caption)
				.fontWeight(.semibold)

			Spacer(minLength: 8)

			Button(action: onAddRepository) {
				Label("Add Repository", systemImage: "plus")
					.labelStyle(.iconOnly)
			}
			.buttonStyle(.plain)
			.font(.system(size: 11, weight: .semibold))
			.frame(width: 20, height: 20)
			.keyboardShortcut("t", modifiers: .command)
			.accessibilityLabel("Add Repository")
			.help("Add Repository")
		}
		.textCase(nil)
		.frame(minHeight: 22)
		.padding(.trailing, 2)
		.accessibilityElement(children: .contain)
	}
}

private struct RepositoryRow: View {
	@ObservedObject var workspace: WorkspaceViewModel
	let repositoryName: String
	let isSelected: Bool

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "folder")
				.font(.system(size: 13, weight: .medium))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(isSelected ? Color.accentColor : .secondary)
				.frame(width: 16, alignment: .center)

			Text(repositoryName)
				.fontWeight(.medium)
				.foregroundStyle(.primary)
				.lineLimit(1)
				.layoutPriority(1)

			Text(workspace.currentBranchName)
				.font(.caption2)
				.foregroundStyle(.tertiary)
				.lineLimit(1)
				.truncationMode(.middle)
				.frame(maxWidth: 76, alignment: .trailing)

			if workspace.isLoading {
				ProgressView()
					.controlSize(.mini)
					.accessibilityLabel("Refreshing Repository")
			}
		}
		.frame(minHeight: 22)
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(repositoryName)
		.accessibilityValue(workspace.currentBranchName)
	}
}

private struct SidebarSectionRow: View {
	let section: WorkspaceSection
	let badgeCount: Int?

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: section.systemImage)
				.font(.system(size: 13, weight: .regular))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 16, alignment: .center)
				.accessibilityHidden(true)

			Text(section.title)
				.lineLimit(1)

			Spacer(minLength: 8)

			if let badgeCount, badgeCount > 0 {
				Text(badgeCount, format: .number)
					.font(.caption)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
		}
		.frame(minHeight: 22)
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(section.title)
		.accessibilityValue(badgeCount.flatMap { $0 > 0 ? String($0) : nil } ?? "")
	}
}
