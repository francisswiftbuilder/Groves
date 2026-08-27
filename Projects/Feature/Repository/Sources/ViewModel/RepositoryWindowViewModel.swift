import Foundation

@MainActor
final class RepositoryWindowViewModel: ObservableObject {
	@Published private(set) var folderImportRequest: RepositoryFolderImportRequest?
	@Published var sidebarSelection: RepositorySidebarSelection?
	@Published var cloneRemoteURL = ""

	var isFolderImporterPresented: Bool {
		folderImportRequest != nil
	}

	var trimmedCloneRemoteURL: String {
		cloneRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func didPresentRepositoryImporter() {
		folderImportRequest = .openRepository
	}

	func didPresentCloneDestinationImporter() {
		guard !trimmedCloneRemoteURL.isEmpty else { return }
		folderImportRequest = .clone(remoteURL: trimmedCloneRemoteURL)
	}

	func didDismissFolderImporter() {
		folderImportRequest = nil
	}

	func consumeFolderImportRequest() -> RepositoryFolderImportRequest? {
		defer { folderImportRequest = nil }
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
