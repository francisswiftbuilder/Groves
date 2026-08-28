import CoreRepositoryUI
import FeatureRepositoryInterface
import SwiftUI

public struct ChangesView: View {
	@ObservedObject private var viewModel: ChangesViewModel
	private let diffViewModel: ChangesDiffViewModel
	@ObservedObject private var commitViewModel: CommitViewModel
	@ObservedObject private var conflictViewModel: ConflictViewModel
	@ObservedObject private var diffPreferences: WorkspaceDiffPreferences
	private let repositoryName: String
	private let currentBranchStatus: String
	private let repositoryURL: URL?
	private let onDiffOptionsChanged: () -> Void

	public init(
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
		_viewModel = ObservedObject(wrappedValue: viewModel)
		self.diffViewModel = diffViewModel
		_commitViewModel = ObservedObject(wrappedValue: commitViewModel)
		_conflictViewModel = ObservedObject(wrappedValue: conflictViewModel)
		_diffPreferences = ObservedObject(wrappedValue: diffPreferences)
		self.repositoryName = repositoryName
		self.currentBranchStatus = currentBranchStatus
		self.repositoryURL = repositoryURL
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	public var body: some View {
		ConflictPresentationHost(viewModel: conflictViewModel) {
			EqualWidthHSplitView(
				proportions: [0.27, 0.50, 0.23],
				minimumWidths: [200, 300, 210]
			) {
				ChangesListView(
					viewModel: viewModel,
					commitViewModel: commitViewModel,
					conflictViewModel: conflictViewModel,
					repositoryURL: repositoryURL
				)
				.frame(maxWidth: .infinity)
			} center: {
				ChangesDiffPane(
					viewModel: viewModel,
					diffViewModel: diffViewModel,
					conflictViewModel: conflictViewModel,
					preferences: diffPreferences,
					repositoryURL: repositoryURL,
					onOptionsChanged: onDiffOptionsChanged
				)
				.frame(maxWidth: .infinity)
			} trailing: {
				ChangesInspectorPane(viewModel: viewModel, diffViewModel: diffViewModel)
					.frame(maxWidth: .infinity)
			}
		}
		.navigationTitle(repositoryName)
		.navigationSubtitle(currentBranchStatus)
		.safeAreaInset(edge: .bottom) {
			CommitBar(viewModel: commitViewModel)
		}
		.confirmationDialog(
			viewModel.pendingConfirmation?.title ?? "Confirm Changes",
			isPresented: pendingConfirmationPresentation
		) {
			if let confirmation = viewModel.pendingConfirmation {
				Button(confirmation.actionTitle, role: .destructive) {
					viewModel.didConfirmPendingConfirmation()
				}
			}
			Button("Cancel", role: .cancel) {
				viewModel.didDismissPendingConfirmation()
			}
		} message: {
			Text(viewModel.pendingConfirmation?.message ?? "")
		}
	}

	private var pendingConfirmationPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingConfirmation != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissPendingConfirmation()
				}
			}
		)
	}
}
