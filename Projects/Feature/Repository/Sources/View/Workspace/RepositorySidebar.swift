import DomainGitInterface
import SwiftUI

struct RepositorySidebar: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	let repositories: [RepositoryTab]
	let selectedRepositoryID: RepositoryTab.ID?
	@Binding var selectedItem: RepositorySidebarSelection?
	let onSelectRepository: (RepositoryTab.ID) -> Void
	let onCloseRepository: (RepositoryTab.ID) -> Void
	let onAddRepository: () -> Void
	@State private var expandedRepositoryIDs: Set<RepositoryTab.ID> = []
	@State private var expandedGroups: Set<RepositorySidebarGroup> = []

	var body: some View {
		List(selection: $selectedItem) {
			Section("Repositories") {
				ForEach(repositories) { repository in
					DisclosureGroup(isExpanded: expansionBinding(for: repository.id)) {
						RepositoryNavigationRows(
							workspace: repository.workspace,
							repositoryID: repository.id,
							expandedGroups: $expandedGroups
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
							Button("Refresh", systemImage: "arrow.clockwise") {
								selectRepository(repository.id)
								repository.workspace.didRequestRefresh()
							}

							Divider()

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
			}
		}
		.listStyle(.sidebar)
		.contextMenu(forSelectionType: RepositorySidebarSelection.self) { selections in
			sidebarContextMenu(for: selections)
		} primaryAction: { selections in
			performPrimaryAction(for: selections)
		}
		.safeAreaInset(edge: .bottom) {
			RepositorySidebarBottomBar(
				viewModel: viewModel,
				hasSelectedRepository: selectedRepositoryID != nil,
				onAddRepository: onAddRepository,
				onSelectSection: selectSection,
				onCloseRepository: closeSelectedRepository
			)
		}
		.onAppear {
			expandSelectedRepository()
		}
		.onChange(of: selectedRepositoryID) { _, _ in
			expandSelectedRepository()
		}
	}

	private var expansionAnimation: Animation? {
		reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)
	}

	@ViewBuilder
	private func sidebarContextMenu(
		for selections: Set<RepositorySidebarSelection>
	) -> some View {
		if selections.count == 1,
			let selection = selections.first,
			let repository = repositories.first(where: { $0.id == selection.repositoryID })
		{
			switch selection {
			case .branch(_, let id):
				if let branch = repository.workspace.branches.first(where: { $0.id == id }) {
					Button("Switch to \(branch.name)", systemImage: "arrow.triangle.branch") {
						selectBranch(branch, in: repository)
						repository.workspace.didRequestSwitchBranch()
					}
					.disabled(branch.isCurrent)

					Button("Delete Branch", systemImage: "trash", role: .destructive) {
						selectBranch(branch, in: repository)
						repository.workspace.didRequestDeleteBranch()
					}
					.disabled(branch.isCurrent)
				}
			case .stash(_, let id):
				if let stash = repository.workspace.stashes.first(where: { $0.id == id }) {
					Button("Apply Stash", systemImage: "arrow.down.doc") {
						selectStash(stash, in: repository)
						repository.workspace.didRequestApplyStash()
					}

					Button("Pop Stash", systemImage: "arrow.up.doc") {
						selectStash(stash, in: repository)
						repository.workspace.didRequestPopStash()
					}

					Divider()

					Button("Delete Stash", systemImage: "trash", role: .destructive) {
						selectStash(stash, in: repository)
						repository.workspace.didRequestDropStash()
					}
				}
			case .section, .remote, .remoteBranch, .tag:
				EmptyView()
			}
		}
	}

	private func performPrimaryAction(
		for selections: Set<RepositorySidebarSelection>
	) {
		guard
			selections.count == 1,
			let selection = selections.first,
			case .branch(_, let id) = selection,
			let repository = repositories.first(where: { $0.id == selection.repositoryID }),
			let branch = repository.workspace.branches.first(where: { $0.id == id })
		else { return }

		selectBranch(branch, in: repository)
		repository.workspace.didRequestSwitchBranch()
	}

	private func selectBranch(_ branch: GitBranch, in repository: RepositoryTab) {
		selectedItem = .branch(repositoryID: repository.id, id: branch.id)
		selectRepository(repository.id)
		repository.workspace.selectedBranchID = branch.id
	}

	private func selectStash(_ stash: GitStash, in repository: RepositoryTab) {
		selectedItem = .stash(repositoryID: repository.id, id: stash.id)
		selectRepository(repository.id)
		repository.workspace.selectedStashID = stash.id
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

	private func selectSection(_ section: WorkspaceSection) {
		guard let selectedRepositoryID else { return }
		selectedItem = .section(repositoryID: selectedRepositoryID, section: section)
		expandGroupIfNeeded(section, repositoryID: selectedRepositoryID)
	}

	private func expandGroupIfNeeded(
		_ section: WorkspaceSection,
		repositoryID: RepositoryTab.ID
	) {
		guard let kind = RepositorySidebarGroupKind(section: section) else { return }
		expandedGroups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
	}

	private func closeSelectedRepository() {
		guard let selectedRepositoryID else { return }
		closeRepository(selectedRepositoryID)
	}

	private func closeRepository(_ repositoryID: RepositoryTab.ID) {
		withAnimation(expansionAnimation) {
			expandedRepositoryIDs.remove(repositoryID)
			expandedGroups = expandedGroups.filter { $0.repositoryID != repositoryID }
		}
		onCloseRepository(repositoryID)
	}

	private func expandSelectedRepository() {
		guard let selectedRepositoryID else { return }
		expandRepository(selectedRepositoryID)
		expandDefaultGroups(repositoryID: selectedRepositoryID)
		if let selectedSection = viewModel.selectedSection {
			expandGroupIfNeeded(selectedSection, repositoryID: selectedRepositoryID)
		}
	}

	private func expandDefaultGroups(repositoryID: RepositoryTab.ID) {
		for kind in RepositorySidebarGroupKind.allCases {
			expandedGroups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
		}
	}

	private func expandRepository(_ repositoryID: RepositoryTab.ID) {
		guard !expandedRepositoryIDs.contains(repositoryID) else { return }
		withAnimation(expansionAnimation) {
			_ = expandedRepositoryIDs.insert(repositoryID)
		}
	}
}

private struct RepositoryNavigationRows: View {
	@ObservedObject var workspace: WorkspaceViewModel
	let repositoryID: RepositoryTab.ID
	@Binding var expandedGroups: Set<RepositorySidebarGroup>

	var body: some View {
		sectionRow(.tree)
		sectionRow(.changes, badgeCount: workspace.changes.count)
		sectionRow(.history)

		navigationGroup(.branches, kind: .branches, selectsSection: false) {
			ForEach(workspace.branches) { branch in
				BranchSidebarRow(branch: branch)
					.tag(RepositorySidebarSelection.branch(repositoryID: repositoryID, id: branch.id))
					.help("Click to show \(branch.name) in History. Double-click to switch branches.")
			}
		}

		navigationGroup(.remotes, kind: .remotes, selectsSection: false) {
			ForEach(workspace.remotes) { remote in
				DisclosureGroup {
					ForEach(remote.branches) { branch in
						RemoteBranchSidebarRow(branch: branch)
							.tag(
								RepositorySidebarSelection.remoteBranch(
									repositoryID: repositoryID,
									id: branch.id
								)
							)
							.help("Show \(branch.fullName) in History")
					}
				} label: {
					SidebarChildRow(title: remote.name, systemImage: "icloud", accessory: nil)
				}
			}
		}

		tagNavigationGroup {
			ForEach(workspace.tags) { tag in
				TagSidebarRow(tag: tag)
					.tag(RepositorySidebarSelection.tag(repositoryID: repositoryID, id: tag.id))
					.help("Show \(tag.name) in History")
			}
		}

		navigationGroup(.stashes, kind: .stashes) {
			ForEach(workspace.stashes) { stash in
				SidebarChildRow(
					title: stash.subject,
					systemImage: "archivebox",
					accessory: stash.reference
				)
				.tag(RepositorySidebarSelection.stash(repositoryID: repositoryID, id: stash.id))
			}
		}
	}

	private func sectionRow(_ section: WorkspaceSection, badgeCount: Int? = nil) -> some View {
		SidebarSectionRow(section: section, badgeCount: badgeCount)
			.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
	}

	@ViewBuilder
	private func navigationGroup<Content: View>(
		_ section: WorkspaceSection,
		kind: RepositorySidebarGroupKind,
		selectsSection: Bool = true,
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		let group = RepositorySidebarGroup(
			repositoryID: repositoryID,
			kind: kind
		)
		let disclosureGroup = DisclosureGroup(
			isExpanded: Binding(
				get: { expandedGroups.contains(group) },
				set: { isExpanded in
					if isExpanded {
						expandedGroups.insert(group)
					} else {
						expandedGroups.remove(group)
					}
				}
			)
		) {
			content()
		} label: {
			SidebarSectionRow(section: section, badgeCount: nil)
		}

		if selectsSection {
			disclosureGroup
				.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
		} else {
			disclosureGroup
		}
	}

	private func tagNavigationGroup<Content: View>(
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: .tags)
		return DisclosureGroup(
			isExpanded: Binding(
				get: { expandedGroups.contains(group) },
				set: { isExpanded in
					if isExpanded {
						expandedGroups.insert(group)
					} else {
						expandedGroups.remove(group)
					}
				}
			)
		) {
			content()
		} label: {
			SidebarGroupRow(title: "Tags", systemImage: "tag")
		}
	}

}

private struct RepositorySidebarGroup: Hashable {
	let repositoryID: RepositoryTab.ID
	let kind: RepositorySidebarGroupKind
}

private enum RepositorySidebarGroupKind: CaseIterable, Hashable {
	case branches
	case remotes
	case tags
	case stashes

	init?(section: WorkspaceSection) {
		switch section {
		case .branches:
			self = .branches
		case .remotes:
			self = .remotes
		case .stashes:
			self = .stashes
		case .changes, .history, .tree:
			return nil
		}
	}
}

private struct SidebarGroupRow: View {
	let title: String
	let systemImage: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.font(.system(size: 13))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 16)
				.accessibilityHidden(true)

			Text(title)
				.lineLimit(1)
		}
		.frame(minHeight: 22)
		.contentShape(.rect)
	}
}

private struct RepositoryRow: View {
	@ObservedObject var workspace: WorkspaceViewModel
	let repositoryName: String
	let isSelected: Bool

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: isSelected ? "folder.fill" : "folder")
				.font(.system(size: 13, weight: .medium))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(isSelected ? Color.accentColor : .secondary)
				.frame(width: 16)

			Text(repositoryName)
				.fontWeight(.semibold)
				.lineLimit(1)
				.layoutPriority(1)

			Spacer(minLength: 4)

			Text(workspace.currentBranchName)
				.font(.caption2)
				.foregroundStyle(.tertiary)
				.lineLimit(1)
				.truncationMode(.middle)

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
				.font(.system(size: 13))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 16)
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
	}
}

private struct BranchSidebarRow: View {
	let branch: GitBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch",
			accessory: branch.isCurrent ? "Current" : nil
		)
	}
}

private struct RemoteBranchSidebarRow: View {
	let branch: GitRemoteBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: "arrow.triangle.branch",
			accessory: nil
		)
	}
}

private struct TagSidebarRow: View {
	let tag: GitTag

	var body: some View {
		SidebarChildRow(title: tag.name, systemImage: "tag", accessory: nil)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct SidebarChildRow: View {
	let title: String
	let systemImage: String
	let accessory: String?

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.font(.system(size: 11))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.frame(width: 14)

			Text(title)
				.lineLimit(1)

			Spacer(minLength: 6)

			if let accessory {
				Text(accessory)
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
		.contentShape(.rect)
	}
}

private struct RepositorySidebarBottomBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	let hasSelectedRepository: Bool
	let onAddRepository: () -> Void
	let onSelectSection: (WorkspaceSection) -> Void
	let onCloseRepository: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Menu("New", systemImage: "plus") {
				Button("Add Repository…", systemImage: "folder.badge.plus", action: onAddRepository)
					.keyboardShortcut("t", modifiers: .command)

				Divider()

				Button("New Branch…", systemImage: "arrow.triangle.branch") {
					onSelectSection(.branches)
				}
				.disabled(!hasSelectedRepository)

				Button("Stash Changes…", systemImage: "archivebox") {
					onSelectSection(.stashes)
				}
				.disabled(!hasSelectedRepository || viewModel.changes.isEmpty)
			}
			.menuStyle(.borderlessButton)
			.fixedSize()

			Spacer()

			Menu {
				Button("Refresh", systemImage: "arrow.clockwise") {
					viewModel.didRequestRefresh()
				}
				.disabled(!hasSelectedRepository || viewModel.isLoading)

				Divider()

				Button("Close Repository", systemImage: "xmark", role: .destructive) {
					onCloseRepository()
				}
				.disabled(!hasSelectedRepository)
			} label: {
				Label("Repository Actions", systemImage: "gearshape")
					.labelStyle(.iconOnly)
			}
			.menuStyle(.borderlessButton)
			.fixedSize()
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(.bar)
	}
}
