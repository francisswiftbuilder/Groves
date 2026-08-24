import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RepositoryTabsView: View {
	@Environment(\.openWindow) private var openWindow
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@Binding var repositoryID: RepositoryTab.ID?
	@State private var isFolderImporterPresented = false
	@State private var folderImportRequest: RepositoryFolderImportRequest?
	@State private var sidebarSelection: RepositorySidebarSelection?
	@State private var isPresentingNewBranch = false
	@State private var newBranchName = ""

	var body: some View {
		Group {
			if let repositoryTab {
				WorkspaceView(
					viewModel: repositoryTab.workspace,
					repositoryID: repositoryTab.id,
					sidebarSelection: $sidebarSelection
				)
			} else {
				RepositoryWelcomeContainerView(
					isWorking: viewModel.isAddingRepository,
					onOpenRepository: presentRepositoryImporter,
					onCloneRepository: presentCloneDestinationImporter
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
		.onChange(of: sidebarSelection) { _, selection in
			activateSidebarSelection(selection)
		}
		.toolbar {
			if let repositoryTab {
				RepositoryWorkspaceToolbar(
					viewModel: repositoryTab.workspace,
					onCreateBranch: presentNewBranch
				)
			}
		}
		.toolbarRole(.editor)
		.fileImporter(
			isPresented: $isFolderImporterPresented,
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
		.alert("New Branch", isPresented: $isPresentingNewBranch) {
			if let repositoryTab {
				TextField("Branch name", text: $newBranchName)
				Button("Cancel", role: .cancel) {
					newBranchName = ""
				}
				Button("Create") {
					repositoryTab.workspace.newBranchName = newBranchName
					repositoryTab.workspace.didRequestCreateBranch()
				}
				.disabled(
					newBranchName
						.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				)
			}
		} message: {
			Text("Create and switch to a new branch from the current branch.")
		}
	}

	private func presentNewBranch() {
		guard repositoryTab != nil else { return }
		newBranchName = ""
		isPresentingNewBranch = true
	}

	private func presentRepositoryImporter() {
		folderImportRequest = .openRepository
		isFolderImporterPresented = true
	}

	private func presentCloneDestinationImporter(remoteURL: String) {
		folderImportRequest = .clone(remoteURL: remoteURL)
		isFolderImporterPresented = true
	}

	private func handleFolderImport(_ result: Result<[URL], any Error>) {
		guard let request = folderImportRequest else { return }
		folderImportRequest = nil

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
		guard let id, viewModel.tab(id: id) != nil else {
			sidebarSelection = nil
			return
		}

		viewModel.didSelectTab(id)
		if sidebarSelection?.repositoryID != id {
			sidebarSelection = viewModel.defaultSidebarSelection(repositoryID: id)
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
