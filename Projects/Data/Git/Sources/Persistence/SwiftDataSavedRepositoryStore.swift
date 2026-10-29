import DomainGitInterface
import Foundation
import SwiftData

@MainActor
public final class SwiftDataSavedRepositoryStore: SavedRepositoryStore {
	private let container: ModelContainer
	private let context: ModelContext
	private var accessedURLs: [UUID: URL] = [:]
	private var resourceIdentifiers: [UUID: NSObject] = [:]

	public convenience init(isStoredInMemoryOnly: Bool = false) throws {
		let configuration = ModelConfiguration(
			"Groves",
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

	deinit {
		for url in accessedURLs.values {
			url.stopAccessingSecurityScopedResource()
		}
	}

	public func requestRepositories() throws -> [SavedRepository] {
		let records = try requestRecords()
		var occupiedPaths = Set(records.map(\.path))
		let repositories: [SavedRepository]
		do {
			repositories = try records.map {
				try requestResolveRepository($0, occupiedPaths: &occupiedPaths)
			}
		} catch {
			context.rollback()
			throw error
		}
		if context.hasChanges {
			do {
				try context.save()
			} catch {
				context.rollback()
			}
		}
		return repositories
	}

	public func requestSaveRepository(at url: URL) throws -> SavedRepository {
		let standardizedURL = url.standardizedFileURL
		let bookmarkData = try requestBookmarkData(for: standardizedURL)
		let records = try requestRecords()
		let resourceIdentifier = requestResourceIdentifier(for: standardizedURL)
		let record: SavedRepositoryRecord
		if let existingRecord = records.first(where: { record in
			if let existingIdentifier = resourceIdentifiers[record.id], let resourceIdentifier {
				return existingIdentifier.isEqual(resourceIdentifier)
			}
			let resolvedURL =
				requestBookmarkedURL(for: record)?.url
				?? URL(fileURLWithPath: record.path, isDirectory: true).standardizedFileURL
			return resolvedURL == standardizedURL
		}) {
			if records.contains(where: { $0.id != existingRecord.id && $0.path == standardizedURL.path })
				== false
			{
				existingRecord.path = standardizedURL.path
			}
			existingRecord.name = standardizedURL.lastPathComponent
			existingRecord.bookmarkData = bookmarkData
			record = existingRecord
		} else {
			guard records.contains(where: { $0.path == standardizedURL.path }) == false else {
				throw SavedRepositoryStoreError.bookmarkResolutionFailed
			}
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
		resourceIdentifiers[record.id] = resourceIdentifier
		var occupiedPaths = Set(records.map(\.path))
		return try requestResolveRepository(record, occupiedPaths: &occupiedPaths)
	}

	public func requestRemoveRepository(id: UUID, selecting selectedRepositoryID: UUID?) throws {
		let records = try requestRecords()
		guard let record = records.first(where: { $0.id == id }) else { return }
		context.delete(record)
		for remainingRecord in records where remainingRecord.id != id {
			remainingRecord.isSelected = remainingRecord.id == selectedRepositoryID
		}
		try requestSaveContext()
		resourceIdentifiers.removeValue(forKey: id)
		if let url = accessedURLs.removeValue(forKey: id) {
			url.stopAccessingSecurityScopedResource()
		}
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
		_ record: SavedRepositoryRecord,
		occupiedPaths: inout Set<String>
	) throws -> SavedRepository {
		let resolution = requestBookmarkedURL(for: record)
		let url =
			resolution?.url
			?? URL(
				fileURLWithPath: record.path,
				isDirectory: true
			).standardizedFileURL

		if requestIsDirectory(at: url) {
			if let identifier = requestResourceIdentifier(for: url) {
				if let previousIdentifier = resourceIdentifiers[record.id],
					previousIdentifier.isEqual(identifier) == false
				{
					throw SavedRepositoryStoreError.bookmarkResolutionFailed
				}
				resourceIdentifiers[record.id] = identifier
			}
			if accessedURLs[record.id] != url, url.startAccessingSecurityScopedResource() {
				accessedURLs[record.id]?.stopAccessingSecurityScopedResource()
				accessedURLs[record.id] = url
			}

			if record.path != url.path, occupiedPaths.contains(url.path) == false {
				occupiedPaths.insert(url.path)
				record.path = url.path
			}
			if record.name != url.lastPathComponent {
				record.name = url.lastPathComponent
			}
			if resolution == nil || resolution?.isStale == true {
				if let bookmarkData = try? requestBookmarkData(for: url) {
					record.bookmarkData = bookmarkData
				}
			}
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

	private func requestIsDirectory(at url: URL) -> Bool {
		var isDirectory: ObjCBool = false
		return FileManager.default.fileExists(
			atPath: url.path,
			isDirectory: &isDirectory
		) && isDirectory.boolValue
	}

	private func requestResourceIdentifier(for url: URL) -> NSObject? {
		let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
		return values?.fileResourceIdentifier as? NSObject
	}

	private func requestSaveContext() throws {
		do {
			try context.save()
		} catch {
			context.rollback()
			throw SavedRepositoryStoreError.persistenceFailed
		}
	}
}
