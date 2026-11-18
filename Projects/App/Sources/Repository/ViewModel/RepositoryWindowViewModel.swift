import Foundation
import Observation

@MainActor
@Observable
final class RepositoryWindowViewModel {
	private(set) var folderImportRequest: RepositoryFolderImportRequest?
	private(set) var isFolderImporterPresented = false
	var sidebarSelection: RepositorySidebarSelection?

	func didPresentRepositoryImporter() {
		folderImportRequest = .openRepository
		isFolderImporterPresented = true
	}

	func didPresentCloneDestinationImporter(remoteURL: String) {
		guard !isFolderImporterPresented, let url = Self.cloneRemoteURL(from: remoteURL) else {
			return
		}
		folderImportRequest = .clone(remoteURL: url)
		isFolderImporterPresented = true
	}

	static func cloneRemoteURL(from query: String) -> String? {
		let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let gitHubPrefix = "git@github.com:"
		let candidate =
			text.hasPrefix(gitHubPrefix)
			? "https://github.com/" + text.dropFirst(gitHubPrefix.count)
			: text
		guard
			candidate.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
			let components = URLComponents(string: candidate),
			let scheme = components.scheme?.lowercased(),
			let host = components.host?.lowercased(), !host.isEmpty,
			!components.path.split(separator: "/").isEmpty,
			components.password == nil, components.query == nil, components.fragment == nil
		else { return nil }
		switch scheme {
		case "https" where components.user == nil:
			return candidate
		case "ssh", "git+ssh":
			guard components.user == "git",
				(host == "github.com" && [nil, 22].contains(components.port))
					|| (scheme == "ssh" && host == "ssh.github.com" && components.port == 443)
			else { return nil }
			return candidate
		default:
			return nil
		}
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
