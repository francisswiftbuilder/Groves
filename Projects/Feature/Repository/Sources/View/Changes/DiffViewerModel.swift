import Combine
import Foundation

@MainActor
final class DiffViewerModel: ObservableObject {
	@Published private(set) var document = DiffDocument.empty
	@Published private(set) var isParsing = false

	func update(diff: String) async {
		isParsing = true
		document = .empty
		defer { isParsing = false }
		let document = await Task.detached(priority: .userInitiated) {
			DiffDocument(lines: DiffParser.parse(diff).filter { $0.kind != .metadata })
		}.value
		guard !Task.isCancelled else { return }
		self.document = document
	}
}
