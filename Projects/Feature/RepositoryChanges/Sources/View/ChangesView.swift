import CoreRepositoryDiff
import CoreRepositoryUI
import SwiftUI

public struct ChangesView: View {
	private let diffSearchViewModel: RepositorySearchViewModel
	private let viewModel: ChangesViewModel
	private let diffViewModel: ChangesDiffViewModel
	private let commitViewModel: CommitViewModel
	private let conflictViewModel: ConflictViewModel
	private let diffPreferences: WorkspaceDiffPreferences
	private let repositoryName: String
	private let currentBranchStatus: String
	private let repositoryURL: URL?
	private let onDiffOptionsChanged: () -> Void

	public init(
		diffSearchViewModel: RepositorySearchViewModel,
		viewModel: ChangesViewModel,
		diffViewModel: ChangesDiffViewModel,
		commitViewModel: CommitViewModel,
		conflictViewModel: ConflictViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		repositoryName: String,
		currentBranchStatus: String,
		repositoryURL: URL?,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		self.diffSearchViewModel = diffSearchViewModel
		self.viewModel = viewModel
		self.diffViewModel = diffViewModel
		self.commitViewModel = commitViewModel
		self.conflictViewModel = conflictViewModel
		self.diffPreferences = diffPreferences
		self.repositoryName = repositoryName
		self.currentBranchStatus = currentBranchStatus
		self.repositoryURL = repositoryURL
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	public var body: some View {
		EqualWidthHSplitView(
			proportions: [0.27, 0.50, 0.23],
			minimumWidths: [200, 300, 210]
		) {
			ChangesListView(
				viewModel: viewModel,
				conflictViewModel: conflictViewModel,
				repositoryURL: repositoryURL
			)
			.frame(maxWidth: .infinity)
		} center: {
			ConflictPresentationHost(viewModel: conflictViewModel) {
				ChangesDiffPane(
					searchViewModel: diffSearchViewModel,
					viewModel: viewModel,
					diffViewModel: diffViewModel,
					conflictViewModel: conflictViewModel,
					preferences: diffPreferences,
					repositoryURL: repositoryURL,
					onOptionsChanged: onDiffOptionsChanged
				)
				.frame(maxWidth: .infinity)
			}
		} trailing: {
			ChangesInspectorPane(viewModel: viewModel, diffViewModel: diffViewModel)
				.frame(maxWidth: .infinity)
		}
		.navigationTitle(repositoryName)
		.navigationSubtitle(currentBranchStatus)
		.safeAreaInset(edge: .bottom) {
			CommitBar(viewModel: commitViewModel)
		}
	}
}
