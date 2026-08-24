import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum RepositoryFolderImportRequest {
	case openRepository
	case clone(remoteURL: String)
}
