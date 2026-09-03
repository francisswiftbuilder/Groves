import Foundation
import SwiftData
import XCTest

@testable import DataGit

@MainActor
final class SwiftDataSavedRepositoryStoreTests: XCTestCase {
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

		XCTAssertEqual(try store.requestRepositories().map(\.id), [savedRepository.id])

		try store.requestSelectRepository(id: savedRepository.id)

		XCTAssertTrue(try XCTUnwrap(store.requestRepositories().first).isSelected)

		try store.requestRemoveRepository(id: savedRepository.id)

		XCTAssertTrue(try store.requestRepositories().isEmpty)
	}

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

		XCTAssertEqual(firstRepository.id, secondRepository.id)
		XCTAssertEqual(try store.requestRepositories().count, 1)
	}

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
		let repository = try XCTUnwrap(store.requestRepositories().first)

		XCTAssertEqual(repository.id, repositoryID)
		XCTAssertEqual(repository.url.standardizedFileURL, repositoryURL.standardizedFileURL)
	}

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

		XCTAssertEqual(repositories.map(\.id), [unavailableRepositoryID, repositoryID])
		XCTAssertEqual(
			repositories.first?.url.standardizedFileURL,
			unavailableRepositoryURL.standardizedFileURL
		)
		XCTAssertTrue(repositories.first?.isSelected == true)
		XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedRepositoryRecord>()), 2)
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
