import SwiftUI

struct RepositoryCommands: Commands {
	@FocusedValue(\.repositoryActions) private var actions

	var body: some Commands {
		CommandMenu("Repository") {
			Button("Refresh") { actions?.refresh() }
				.keyboardShortcut("r", modifiers: .command)
				.disabled(actions == nil)
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
