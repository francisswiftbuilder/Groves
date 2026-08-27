import Foundation

public enum DiffPresentationMode: String, CaseIterable, Identifiable, Sendable {
	case sideBySide
	case unified

	public var id: Self { self }

	public var title: String {
		switch self {
		case .sideBySide:
			return "Side by Side"
		case .unified:
			return "Unified"
		}
	}

	public var systemImage: String {
		switch self {
		case .sideBySide:
			return "rectangle.split.2x1"
		case .unified:
			return "list.bullet.rectangle"
		}
	}
}
