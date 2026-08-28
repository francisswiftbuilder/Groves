import Foundation

enum RepositoryFolderImportRequest {
	case openRepository
	case clone(remoteURL: String)
}
