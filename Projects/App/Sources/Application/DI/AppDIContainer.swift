import DataGit
import DomainGitInterface
import FeatureRepository
import FeatureRepositoryInterface
import Foundation
import SwiftUI

@MainActor
final class AppDIContainer: RepositoryDIDependencies {
	static let shared = AppDIContainer()
	private let savedRepositoryStoreResult: Result<any SavedRepositoryStore, Error>

	private init() {
		savedRepositoryStoreResult = Result {
			try SwiftDataSavedRepositoryStore()
		}
	}

	func makeGitRepository() -> any GitRepository {
		LocalGitRepository()
	}

	func makeSavedRepositoryStore() throws -> any SavedRepositoryStore {
		try savedRepositoryStoreResult.get()
	}

	func makeRepositoryRootView() -> AnyView {
		DefaultRepositoryDIContainer(dependencies: self).makeRootView()
	}
}
