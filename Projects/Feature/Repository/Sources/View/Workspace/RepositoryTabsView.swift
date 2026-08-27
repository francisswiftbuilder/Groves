import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RepositoryTabsView: View {
	@Environment(\.openWindow) private var openWindow
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	@Binding var repositoryID: RepositoryTab.ID?

	var body: some View {
		Group {
			if let repositoryTab {
				WorkspaceView(
					viewModel: repositoryTab.workspace.viewModel,
					windowViewModel: windowViewModel,
					changesViewModel: repositoryTab.workspace.changesViewModel,
					historyViewModel: repositoryTab.workspace.historyViewModel,
					operationViewModel: repositoryTab.workspace.operationViewModel,
					stashesViewModel: repositoryTab.workspace.stashesViewModel,
					treeViewModel: repositoryTab.workspace.treeViewModel,
					diffPreferences: repositoryTab.workspace.diffPreferences,
					repositoryID: repositoryTab.id
				)
			} else {
				RepositoryWelcomeContainerView(
					viewModel: windowViewModel,
					isWorking: viewModel.isAddingRepository,
					onOpenRepository: presentRepositoryImporter,
					onCloneRepository: presentCloneDestinationImporter,
					onCancel: viewModel.didRequestCancelAddingRepository
				)
			}
		}
		.navigationTitle(repositoryTab?.repository.name ?? "New Tab")
		.task {
			restoreRepositoryWindows()
		}
		.onChange(of: repositoryID) { _, id in
			activateRepository(id)
		}
		.onChange(of: windowViewModel.sidebarSelection) { _, selection in
			activateSidebarSelection(selection)
		}
		.toolbar {
			if let repositoryTab {
				RepositoryWorkspaceToolbar(
					viewModel: repositoryTab.workspace.viewModel,
					operationViewModel: repositoryTab.workspace.operationViewModel,
					onCreateBranch: presentNewBranch
				)
			}
		}
		.toolbarRole(.editor)
		.fileImporter(
			isPresented: folderImporterPresentation,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: false
		) { handleFolderImport($0) }
		.alert(
			"Repository Error",
			isPresented: Binding(
				get: { viewModel.alertMessage != nil },
				set: { isPresented in
					if !isPresented {
						viewModel.alertMessage = nil
					}
				}
			),
			actions: {
				Button("OK") {
					viewModel.alertMessage = nil
				}
			},
			message: {
				Text(viewModel.alertMessage ?? "")
			}
		)
	}

	private func presentNewBranch() {
		repositoryTab?.workspace.operationViewModel.didPresentNewBranch()
	}

	private func presentRepositoryImporter() {
		windowViewModel.didPresentRepositoryImporter()
	}

	private func presentCloneDestinationImporter() {
		windowViewModel.didPresentCloneDestinationImporter()
	}

	private func handleFolderImport(_ result: Result<[URL], any Error>) {
		guard let request = windowViewModel.consumeFolderImportRequest() else { return }

		switch result {
		case .success(let urls):
			guard let url = urls.first else { return }
			switch request {
			case .openRepository:
				viewModel.didChooseRepository(url, onOpen: showRepository)
			case .clone(let remoteURL):
				viewModel.didRequestCloneRepository(
					from: remoteURL,
					into: url,
					onOpen: showRepository
				)
			}
		case .failure(let error):
			guard isUserCancellation(error) == false else { return }
			viewModel.alertMessage = error.localizedDescription
		}
	}

	private func isUserCancellation(_ error: any Error) -> Bool {
		let error = error as NSError
		return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
	}

	private var repositoryTab: RepositoryTab? {
		viewModel.tab(id: repositoryID)
	}

	private var folderImporterPresentation: Binding<Bool> {
		Binding(
			get: { windowViewModel.isFolderImporterPresented },
			set: { _ in }
		)
	}

	private func restoreRepositoryWindows() {
		guard
			let restoration = viewModel.requestWindowRestoration(
				currentRepositoryID: repositoryID
			)
		else {
			activateRepository(repositoryID)
			return
		}

		repositoryID = restoration.primaryRepositoryID
		activateRepository(repositoryID)
		for id in restoration.additionalRepositoryIDs {
			openWindow(id: "repository", value: id)
		}
	}

	private func activateRepository(_ id: RepositoryTab.ID?) {
		Task { @MainActor in
			await Task.yield()
			guard let id, viewModel.tab(id: id) != nil else {
				await windowViewModel.didSelectSidebarItem(nil)
				return
			}

			viewModel.didSelectTab(id)
			if windowViewModel.sidebarSelection?.repositoryID != id {
				await windowViewModel.didSelectSidebarItem(
					viewModel.defaultSidebarSelection(repositoryID: id)
				)
			}
		}
	}

	private func activateSidebarSelection(_ selection: RepositorySidebarSelection?) {
		guard let selection else { return }
		viewModel.didActivateSidebarSelection(selection)
		if selection.repositoryID != repositoryID {
			openRepository(selection.repositoryID)
		}
	}

	private func openRepository(_ id: RepositoryTab.ID) {
		guard id != repositoryID else {
			activateRepository(id)
			return
		}
		openWindow(id: "repository", value: id)
	}

	private func showRepository(_ id: RepositoryTab.ID) {
		if repositoryID == nil {
			repositoryID = id
		} else {
			openRepository(id)
		}
	}

}
