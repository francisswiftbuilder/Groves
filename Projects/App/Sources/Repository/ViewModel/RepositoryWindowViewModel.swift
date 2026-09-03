import Foundation

@MainActor
final class RepositoryWindowViewModel: ObservableObject {
	@Published private(set) var folderImportRequest: RepositoryFolderImportRequest?
	@Published private(set) var isFolderImporterPresented = false
	@Published var sidebarSelection: RepositorySidebarSelection?
	@Published var cloneRemoteURL = ""

	var trimmedCloneRemoteURL: String {
		cloneRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func didPresentRepositoryImporter() {
		folderImportRequest = .openRepository
		isFolderImporterPresented = true
	}

	func didPresentCloneDestinationImporter() {
		guard !trimmedCloneRemoteURL.isEmpty else { return }
		folderImportRequest = .clone(remoteURL: trimmedCloneRemoteURL)
		isFolderImporterPresented = true
	}

	func didDismissFolderImporter() {
		isFolderImporterPresented = false
	}

	func consumeFolderImportRequest() -> RepositoryFolderImportRequest? {
		defer {
			folderImportRequest = nil
			isFolderImporterPresented = false
		}
		return folderImportRequest
	}

	func didSelectSidebarItem(_ selection: RepositorySidebarSelection?) async {
		await Task.yield()
		guard !Task.isCancelled, sidebarSelection != selection else { return }
		sidebarSelection = selection
	}

	func selectSidebarItem(_ selection: RepositorySidebarSelection?) {
		guard sidebarSelection != selection else { return }
		sidebarSelection = selection
	}
}
