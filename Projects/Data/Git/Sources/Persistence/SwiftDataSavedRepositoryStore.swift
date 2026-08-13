import DomainGitInterface
import Foundation
import SwiftData

@MainActor
public final class SwiftDataSavedRepositoryStore: SavedRepositoryStore {
	private let container: ModelContainer
	private let context: ModelContext
	private var accessedURLs: [UUID: URL] = [:]

	public convenience init(isStoredInMemoryOnly: Bool = false) throws {
		let configuration = ModelConfiguration(
			"Trees",
			isStoredInMemoryOnly: isStoredInMemoryOnly
		)
		do {
			let container = try ModelContainer(
				for: SavedRepositoryRecord.self,
				configurations: configuration
			)
			self.init(container: container)
		} catch {
			throw SavedRepositoryStoreError.persistenceFailed
		}
	}

	init(container: ModelContainer) {
		self.container = container
		context = ModelContext(container)
		context.autosaveEnabled = false
	}

	public func requestRepositories() throws -> [SavedRepository] {
		let records = try requestRecords()
		var repositories: [SavedRepository] = []

		for record in records {
			do {
				repositories.append(try requestResolveRepository(record))
			} catch SavedRepositoryStoreError.bookmarkResolutionFailed {
				continue
			}
		}

		return repositories
	}

	public func requestSaveRepository(at url: URL) throws -> SavedRepository {
		let standardizedURL = url.standardizedFileURL
		let bookmarkData = try requestBookmarkData(for: standardizedURL)

		let records = try requestRecords()
		let record: SavedRepositoryRecord
		if let existingRecord = records.first(where: { $0.path == standardizedURL.path }) {
			existingRecord.name = standardizedURL.lastPathComponent
			existingRecord.bookmarkData = bookmarkData
			record = existingRecord
		} else {
			record = SavedRepositoryRecord(
				id: UUID(),
				path: standardizedURL.path,
				name: standardizedURL.lastPathComponent,
				bookmarkData: bookmarkData,
				position: (records.map(\.position).max() ?? -1) + 1,
				isSelected: false
			)
			context.insert(record)
		}

		try requestSaveContext()
		return try requestResolveRepository(record)
	}

	public func requestRemoveRepository(id: UUID) throws {
		guard let record = try requestRecords().first(where: { $0.id == id }) else { return }
		if let url = accessedURLs.removeValue(forKey: id) {
			url.stopAccessingSecurityScopedResource()
		}
		context.delete(record)
		try requestSaveContext()
	}

	public func requestSelectRepository(id: UUID?) throws {
		for record in try requestRecords() {
			record.isSelected = record.id == id
		}
		try requestSaveContext()
	}

	private func requestRecords() throws -> [SavedRepositoryRecord] {
		do {
			return try context.fetch(
				FetchDescriptor<SavedRepositoryRecord>(
					sortBy: [SortDescriptor(\.position)]
				)
			)
		} catch {
			throw SavedRepositoryStoreError.persistenceFailed
		}
	}

	private func requestResolveRepository(
		_ record: SavedRepositoryRecord
	) throws -> SavedRepository {
		let resolution = requestBookmarkedURL(for: record)
		let url =
			resolution?.url
			?? URL(
				fileURLWithPath: record.path,
				isDirectory: true
			).standardizedFileURL

		guard requestIsDirectory(at: url) else {
			throw SavedRepositoryStoreError.bookmarkResolutionFailed
		}

		if accessedURLs[record.id] == nil, url.startAccessingSecurityScopedResource() {
			accessedURLs[record.id] = url
		}

		if resolution == nil || resolution?.isStale == true {
			requestRefreshBookmark(for: record, url: url)
		}

		return SavedRepository(
			id: record.id,
			name: record.name,
			url: url,
			position: record.position,
			isSelected: record.isSelected
		)
	}

	private func requestBookmarkedURL(
		for record: SavedRepositoryRecord
	) -> (url: URL, isStale: Bool)? {
		if let resolution = requestResolveBookmark(
			data: record.bookmarkData,
			options: .withSecurityScope
		), requestIsDirectory(at: resolution.url) {
			return resolution
		}

		if let resolution = requestResolveBookmark(
			data: record.bookmarkData,
			options: []
		), requestIsDirectory(at: resolution.url) {
			return resolution
		}

		return nil
	}

	private func requestResolveBookmark(
		data: Data,
		options: URL.BookmarkResolutionOptions
	) -> (url: URL, isStale: Bool)? {
		var isStale = false

		guard
			let url = try? URL(
				resolvingBookmarkData: data,
				options: options,
				relativeTo: nil,
				bookmarkDataIsStale: &isStale
			)
		else {
			return nil
		}

		return (url.standardizedFileURL, isStale)
	}

	private func requestBookmarkData(for url: URL) throws -> Data {
		if let bookmarkData = try? url.bookmarkData(
			options: .withSecurityScope,
			includingResourceValuesForKeys: nil,
			relativeTo: nil
		) {
			return bookmarkData
		}

		if let bookmarkData = try? url.bookmarkData(
			options: [],
			includingResourceValuesForKeys: nil,
			relativeTo: nil
		) {
			return bookmarkData
		}

		throw SavedRepositoryStoreError.bookmarkCreationFailed
	}

	private func requestRefreshBookmark(
		for record: SavedRepositoryRecord,
		url: URL
	) {
		guard let bookmarkData = try? requestBookmarkData(for: url) else { return }

		record.bookmarkData = bookmarkData

		do {
			try context.save()
		} catch {
			context.rollback()
		}
	}

	private func requestIsDirectory(at url: URL) -> Bool {
		var isDirectory: ObjCBool = false
		return FileManager.default.fileExists(
			atPath: url.path,
			isDirectory: &isDirectory
		) && isDirectory.boolValue
	}

	private func requestSaveContext() throws {
		do {
			try context.save()
		} catch {
			throw SavedRepositoryStoreError.persistenceFailed
		}
	}
}
