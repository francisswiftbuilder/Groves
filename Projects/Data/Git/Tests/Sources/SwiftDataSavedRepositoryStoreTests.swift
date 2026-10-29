import Foundation
import SwiftData
import Testing

@testable import DataGit

@MainActor
struct SwiftDataSavedRepositoryStoreTests {
	@Test
	func testSaveSelectAndRemoveRepository() throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		let store = try SwiftDataSavedRepositoryStore(isStoredInMemoryOnly: true)
		let savedRepository = try store.requestSaveRepository(at: repositoryURL)

		#expect(try store.requestRepositories().map(\.id) == [savedRepository.id])

		try store.requestSelectRepository(id: savedRepository.id)

		#expect(try #require(store.requestRepositories().first).isSelected)

		try store.requestRemoveRepository(id: savedRepository.id, selecting: nil)

		#expect(try store.requestRepositories().isEmpty)
	}

	@Test
	func testSavingSameRepositoryDoesNotCreateDuplicate() throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		let store = try SwiftDataSavedRepositoryStore(isStoredInMemoryOnly: true)
		let firstRepository = try store.requestSaveRepository(at: repositoryURL)
		let secondRepository = try store.requestSaveRepository(at: repositoryURL)

		#expect(firstRepository.id == secondRepository.id)
		#expect(try store.requestRepositories().count == 1)
	}

	@Test
	func testRestoringCorruptedBookmarkUsesStoredPath() throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		let container = try requestContainer()
		let context = ModelContext(container)
		let repositoryID = UUID()
		context.insert(
			SavedRepositoryRecord(
				id: repositoryID,
				path: repositoryURL.path,
				name: repositoryURL.lastPathComponent,
				bookmarkData: Data([0, 1, 2]),
				position: 0,
				isSelected: true
			)
		)
		try context.save()

		let store = SwiftDataSavedRepositoryStore(container: container)
		let repository = try #require(store.requestRepositories().first)

		#expect(repository.id == repositoryID)
		#expect(repository.url.standardizedFileURL == repositoryURL.standardizedFileURL)
	}

	@Test
	func testInaccessibleRepositoryRemainsInSavedRepositories() throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		let container = try requestContainer()
		let context = ModelContext(container)
		let unavailableRepositoryID = UUID()
		let unavailableRepositoryURL = repositoryURL.deletingLastPathComponent()
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let repositoryID = UUID()
		context.insert(
			SavedRepositoryRecord(
				id: unavailableRepositoryID,
				path: unavailableRepositoryURL.path,
				name: "Unavailable",
				bookmarkData: Data([0, 1, 2]),
				position: 0,
				isSelected: true
			)
		)
		context.insert(
			SavedRepositoryRecord(
				id: repositoryID,
				path: repositoryURL.path,
				name: repositoryURL.lastPathComponent,
				bookmarkData: Data([0, 1, 2]),
				position: 1,
				isSelected: false
			)
		)
		try context.save()

		let store = SwiftDataSavedRepositoryStore(container: container)
		let repositories = try store.requestRepositories()

		#expect(repositories.map(\.id) == [unavailableRepositoryID, repositoryID])
		#expect(
			repositories.first?.url.standardizedFileURL == unavailableRepositoryURL.standardizedFileURL)
		#expect(repositories.first?.isSelected == true)
		#expect(try context.fetchCount(FetchDescriptor<SavedRepositoryRecord>()) == 2)
	}

	@Test
	func testMovedRepositoryRetainsIdentityAndUpdatedLocationAfterDiskReload() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let originalURL = directory.appendingPathComponent("Original", isDirectory: true)
		let movedURL = directory.appendingPathComponent("Moved", isDirectory: true)
		try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
		let configuration = ModelConfiguration(
			"MoveTests", url: directory.appendingPathComponent("repositories.store"))
		let store = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(for: SavedRepositoryRecord.self, configurations: configuration)
		)
		let saved = try store.requestSaveRepository(at: originalURL)
		try store.requestSelectRepository(id: saved.id)
		try FileManager.default.moveItem(at: originalURL, to: movedURL)

		let moved = try #require(store.requestRepositories().first)
		let reopened = try store.requestSaveRepository(at: movedURL)
		let reloaded = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(for: SavedRepositoryRecord.self, configurations: configuration)
		)
		let repositories = try reloaded.requestRepositories()

		#expect(moved.id == saved.id)
		#expect(moved.name == "Moved")
		#expect(reopened.id == saved.id)
		#expect(repositories.count == 1)
		#expect(repositories.first?.id == saved.id)
		#expect(repositories.first?.url == movedURL.standardizedFileURL)
		#expect(repositories.first?.name == "Moved")
		#expect(repositories.first?.isSelected == true)
	}

	@Test
	func testOpeningMovedRepositoryBeforeReloadDoesNotDuplicateIt() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let originalURL = directory.appendingPathComponent("Original", isDirectory: true)
		let movedURL = directory.appendingPathComponent("Moved", isDirectory: true)
		try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
		let store = try SwiftDataSavedRepositoryStore(isStoredInMemoryOnly: true)
		let saved = try store.requestSaveRepository(at: originalURL)
		try FileManager.default.moveItem(at: originalURL, to: movedURL)

		let reopened = try store.requestSaveRepository(at: movedURL)

		#expect(reopened.id == saved.id)
		#expect(try store.requestRepositories().count == 1)
	}

	@Test
	func testReusingOriginalPathDoesNotOverwriteMovedRepository() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let originalURL = directory.appendingPathComponent("Original", isDirectory: true)
		let movedURL = directory.appendingPathComponent("Moved", isDirectory: true)
		try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
		let store = try SwiftDataSavedRepositoryStore(isStoredInMemoryOnly: true)
		let saved = try store.requestSaveRepository(at: originalURL)
		try FileManager.default.moveItem(at: originalURL, to: movedURL)
		try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)

		#expect(throws: (any Error).self) { try store.requestSaveRepository(at: originalURL) }
		#expect(try store.requestSaveRepository(at: movedURL).id == saved.id)
		let newRepository = try store.requestSaveRepository(at: originalURL)
		let repositories = try store.requestRepositories()

		#expect(newRepository.id != saved.id)
		#expect(repositories.map(\.id) == [saved.id, newRepository.id])
		#expect(
			repositories.map(\.url) == [movedURL.standardizedFileURL, originalURL.standardizedFileURL])
	}

	@Test
	func testLegacyDuplicateBookmarksDoNotMergeOrDeleteSavedRecords() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let bookmark = try directory.bookmarkData(
			options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
		let container = try requestContainer()
		let context = ModelContext(container)
		let ids = [UUID(), UUID()]
		for (position, id) in ids.enumerated() {
			context.insert(
				SavedRepositoryRecord(
					id: id,
					path: directory.appendingPathComponent("Old\(position)").path,
					name: "Old\(position)",
					bookmarkData: bookmark,
					position: position,
					isSelected: position == 1
				)
			)
		}
		try context.save()
		let store = SwiftDataSavedRepositoryStore(container: container)

		#expect(try store.requestRepositories().map(\.id) == ids)
		#expect(try store.requestRepositories().map(\.id) == ids)
		let records = try ModelContext(container).fetch(FetchDescriptor<SavedRepositoryRecord>())
		#expect(Set(records.map(\.id)) == Set(ids))
		#expect(Set(records.map(\.path)).count == 2)
		#expect(try store.requestSaveRepository(at: directory).id == ids.first)
		#expect(try store.requestRepositories().count == 2)
	}

	@Test
	func testRemovalAndNextSelectionPersistTogetherOnDisk() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let firstURL = directory.appendingPathComponent("First", isDirectory: true)
		let secondURL = directory.appendingPathComponent("Second", isDirectory: true)
		try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)
		let configuration = ModelConfiguration(
			"RemovalTests", url: directory.appendingPathComponent("repositories.store"))
		let store = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(for: SavedRepositoryRecord.self, configurations: configuration)
		)
		let first = try store.requestSaveRepository(at: firstURL)
		let second = try store.requestSaveRepository(at: secondURL)
		try store.requestSelectRepository(id: first.id)

		try store.requestRemoveRepository(id: first.id, selecting: second.id)

		let reloaded = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(for: SavedRepositoryRecord.self, configurations: configuration)
		)
		let repositories = try reloaded.requestRepositories()
		#expect(repositories.map(\.id) == [second.id])
		#expect(repositories.first?.isSelected == true)
	}

	@Test
	func testFailedDiskSaveRollsBackDeletionAndSelection() throws {
		let directory = try requestTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let firstURL = directory.appendingPathComponent("First", isDirectory: true)
		let secondURL = directory.appendingPathComponent("Second", isDirectory: true)
		try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)
		let storeURL = directory.appendingPathComponent("repositories.store")
		let store = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(
				for: SavedRepositoryRecord.self,
				configurations: ModelConfiguration("FailureTests", url: storeURL)
			)
		)
		let first = try store.requestSaveRepository(at: firstURL)
		let second = try store.requestSaveRepository(at: secondURL)
		try store.requestSelectRepository(id: first.id)
		let readOnlyStore = SwiftDataSavedRepositoryStore(
			container: try ModelContainer(
				for: SavedRepositoryRecord.self,
				configurations: ModelConfiguration("FailureTests", url: storeURL, allowsSave: false)
			)
		)

		#expect(throws: (any Error).self) {
			try readOnlyStore.requestRemoveRepository(id: first.id, selecting: second.id)
		}
		let afterDeletion = try readOnlyStore.requestRepositories()
		#expect(afterDeletion.map(\.id) == [first.id, second.id])
		#expect(afterDeletion.first(where: \.isSelected)?.id == first.id)
		#expect(throws: (any Error).self) { try readOnlyStore.requestSelectRepository(id: second.id) }
		#expect(try readOnlyStore.requestRepositories().first(where: \.isSelected)?.id == first.id)
		#expect(try store.requestRepositories().map(\.id) == [first.id, second.id])
	}

	private func requestTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func requestContainer() throws -> ModelContainer {
		try ModelContainer(
			for: SavedRepositoryRecord.self,
			configurations: ModelConfiguration(
				"GrovesTests-\(UUID().uuidString)",
				isStoredInMemoryOnly: true
			)
		)
	}
}
