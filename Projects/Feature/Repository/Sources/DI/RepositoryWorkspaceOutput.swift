import FeatureRepositoryChanges

@MainActor
final class RepositoryWorkspaceOutput {
	weak var workspaceViewModel: WorkspaceViewModel?
	weak var changesViewModel: ChangesViewModel?
	weak var changesDiffViewModel: ChangesDiffViewModel?
	weak var conflictViewModel: ConflictViewModel?
}
