import SwiftUI

struct RepositoryCommands: Commands {
	@FocusedValue(\.repositoryActions) private var actions

	var body: some Commands {
		CommandMenu("Repository") {
			Button("New Branch…") { actions?.newBranch?() }
				.disabled(actions?.newBranch == nil)
			Button("Refresh") { actions?.refresh() }
				.keyboardShortcut("r", modifiers: .command)
				.disabled(actions == nil)
			Divider()
			Button("Fetch All Remotes") { actions?.fetchAll?() }
				.disabled(actions?.fetchAll == nil)
			Button("Pull Current Branch") { actions?.pull?() }
				.disabled(actions?.pull == nil)
			if let remoteNames = actions?.pushRemoteNames, !remoteNames.isEmpty {
				Menu("Push Current Branch") {
					ForEach(remoteNames, id: \.self) { remoteName in
						Button(remoteName) { actions?.pushToRemote?(remoteName) }
					}
				}
				.disabled(actions?.pushToRemote == nil)
			} else {
				Button("Push Current Branch") { actions?.push?() }
					.disabled(actions?.push == nil)
			}
			Divider()
			Button("Stage Selected Changes") { actions?.stageSelectedChanges?() }
				.disabled(actions?.stageSelectedChanges == nil)
			Button("Unstage Selected Changes") { actions?.unstageSelectedChanges?() }
				.disabled(actions?.unstageSelectedChanges == nil)
			Button("Stage All Changes") { actions?.stageAllChanges?() }
				.disabled(actions?.stageAllChanges == nil)
			Button("Unstage All Changes") { actions?.unstageAllChanges?() }
				.disabled(actions?.unstageAllChanges == nil)
			Divider()
			Button("View Conflicts") { actions?.viewConflicts?() }
				.disabled(actions?.viewConflicts == nil)
			Button("Continue Operation") { actions?.continueOperation?() }
				.disabled(actions?.continueOperation == nil)
			Button("Skip Commit") { actions?.skipOperation?() }
				.disabled(actions?.skipOperation == nil)
			Button("Abort Operation…") { actions?.abortOperation?() }
				.disabled(actions?.abortOperation == nil)
			Divider()
			Button("Rebase Current Branch onto Selected Branch") {
				actions?.rebaseSelectedBranch?()
			}
			.disabled(actions?.rebaseSelectedBranch == nil)
			Button("Rename Selected Branch…") { actions?.renameSelectedBranch?() }
				.disabled(actions?.renameSelectedBranch == nil)
			Button("Cherry-pick Selected Commit") { actions?.cherryPickSelectedCommit?() }
				.disabled(actions?.cherryPickSelectedCommit == nil)
			Button("Revert Selected Commit") { actions?.revertSelectedCommit?() }
				.disabled(actions?.revertSelectedCommit == nil)
			Button("Reset Current Branch to Selected Commit…") { actions?.resetSelectedCommit?() }
				.disabled(actions?.resetSelectedCommit == nil)
			Divider()
			Button("Add Remote…") { actions?.addRemote?() }
				.disabled(actions?.addRemote == nil)
			Button("Rename Selected Remote…") { actions?.renameSelectedRemote?() }
				.disabled(actions?.renameSelectedRemote == nil)
			Button("Edit Selected Remote URLs…") { actions?.editSelectedRemote?() }
				.disabled(actions?.editSelectedRemote == nil)
			Button("Delete Selected Remote…") { actions?.deleteSelectedRemote?() }
				.disabled(actions?.deleteSelectedRemote == nil)
		}
	}
}
