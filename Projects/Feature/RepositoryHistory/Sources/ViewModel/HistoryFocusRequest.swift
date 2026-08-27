import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

struct HistoryFocusRequest: Equatable {
	let commitID: String
	let isAnimated: Bool
	private let token = UUID()
}
