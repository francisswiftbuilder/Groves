import Foundation

enum RepositoryFolderImportRequest {
	case openRepository
	case clone(remoteURL: String)

	var allowsMultipleSelection: Bool {
		switch self {
		case .openRepository:
			true
		case .clone:
			false
		}
	}
}
