import Foundation

enum DiffPresentationMode: String, CaseIterable, Identifiable, Sendable {
	case sideBySide
	case unified

	var id: Self { self }

	var title: String {
		switch self {
		case .sideBySide:
			return "Side by Side"
		case .unified:
			return "Unified"
		}
	}

	var systemImage: String {
		switch self {
		case .sideBySide:
			return "rectangle.split.2x1"
		case .unified:
			return "list.bullet.rectangle"
		}
	}
}
