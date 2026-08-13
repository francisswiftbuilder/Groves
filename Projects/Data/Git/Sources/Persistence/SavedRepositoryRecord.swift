import Foundation
import SwiftData

@Model
final class SavedRepositoryRecord {
	@Attribute(.unique) var id: UUID
	@Attribute(.unique) var path: String
	var name: String
	var bookmarkData: Data
	var position: Int
	var isSelected: Bool

	init(
		id: UUID,
		path: String,
		name: String,
		bookmarkData: Data,
		position: Int,
		isSelected: Bool
	) {
		self.id = id
		self.path = path
		self.name = name
		self.bookmarkData = bookmarkData
		self.position = position
		self.isSelected = isSelected
	}
}
