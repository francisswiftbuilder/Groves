import Foundation

public struct SavedRepository: Identifiable, Hashable, Sendable {
	public let id: UUID
	public let name: String
	public let url: URL
	public let position: Int
	public let isSelected: Bool

	public init(
		id: UUID,
		name: String,
		url: URL,
		position: Int,
		isSelected: Bool
	) {
		self.id = id
		self.name = name
		self.url = url
		self.position = position
		self.isSelected = isSelected
	}
}
