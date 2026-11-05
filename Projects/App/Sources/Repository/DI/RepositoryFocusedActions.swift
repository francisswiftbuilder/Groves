@MainActor
public struct RepositoryFocusedActions {
	public let refresh: () -> Void
	public let newBranch: (() -> Void)?
	public let fetchAll: (() -> Void)?
	public let pull: (() -> Void)?
	public let push: (() -> Void)?
	public let pushRemoteNames: [String]
	public let pushToRemote: ((String) -> Void)?
	public let stageSelectedChanges: (() -> Void)?
	public let unstageSelectedChanges: (() -> Void)?
	public let stageAllChanges: (() -> Void)?
	public let unstageAllChanges: (() -> Void)?
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
		newBranch: (() -> Void)?,
		fetchAll: (() -> Void)?,
		pull: (() -> Void)?,
		push: (() -> Void)?,
		pushRemoteNames: [String],
		pushToRemote: ((String) -> Void)?,
		stageSelectedChanges: (() -> Void)?,
		unstageSelectedChanges: (() -> Void)?,
		stageAllChanges: (() -> Void)?,
		unstageAllChanges: (() -> Void)?,
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
		self.newBranch = newBranch
		self.fetchAll = fetchAll
		self.pull = pull
		self.push = push
		self.pushRemoteNames = pushRemoteNames
		self.pushToRemote = pushToRemote
		self.stageSelectedChanges = stageSelectedChanges
		self.unstageSelectedChanges = unstageSelectedChanges
		self.stageAllChanges = stageAllChanges
		self.unstageAllChanges = unstageAllChanges
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
