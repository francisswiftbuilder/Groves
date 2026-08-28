@MainActor
public struct RepositoryFocusedActions {
	public let refresh: () -> Void
	public let viewConflicts: (() -> Void)?
	public let continueOperation: (() -> Void)?
	public let skipOperation: (() -> Void)?
	public let abortOperation: (() -> Void)?
	public let rebaseSelectedBranch: (() -> Void)?
	public let renameSelectedBranch: (() -> Void)?
	public let cherryPickSelectedCommit: (() -> Void)?
	public let revertSelectedCommit: (() -> Void)?
	public let resetSelectedCommit: (() -> Void)?
	public let addRemote: (() -> Void)?
	public let renameSelectedRemote: (() -> Void)?
	public let editSelectedRemote: (() -> Void)?
	public let deleteSelectedRemote: (() -> Void)?

	public init(
		refresh: @escaping () -> Void,
		viewConflicts: (() -> Void)?,
		continueOperation: (() -> Void)?,
		skipOperation: (() -> Void)?,
		abortOperation: (() -> Void)?,
		rebaseSelectedBranch: (() -> Void)?,
		renameSelectedBranch: (() -> Void)?,
		cherryPickSelectedCommit: (() -> Void)?,
		revertSelectedCommit: (() -> Void)?,
		resetSelectedCommit: (() -> Void)?,
		addRemote: (() -> Void)?,
		renameSelectedRemote: (() -> Void)?,
		editSelectedRemote: (() -> Void)?,
		deleteSelectedRemote: (() -> Void)?
	) {
		self.refresh = refresh
		self.viewConflicts = viewConflicts
		self.continueOperation = continueOperation
		self.skipOperation = skipOperation
		self.abortOperation = abortOperation
		self.rebaseSelectedBranch = rebaseSelectedBranch
		self.renameSelectedBranch = renameSelectedBranch
		self.cherryPickSelectedCommit = cherryPickSelectedCommit
		self.revertSelectedCommit = revertSelectedCommit
		self.resetSelectedCommit = resetSelectedCommit
		self.addRemote = addRemote
		self.renameSelectedRemote = renameSelectedRemote
		self.editSelectedRemote = editSelectedRemote
		self.deleteSelectedRemote = deleteSelectedRemote
	}
}
