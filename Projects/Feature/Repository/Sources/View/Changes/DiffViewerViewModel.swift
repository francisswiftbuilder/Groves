import Combine
import Foundation

@MainActor
final class DiffViewerViewModel: ObservableObject {
	@Published private(set) var document = DiffDocument.empty
	@Published private(set) var sideBySideRows: [DiffSideBySideRow] = []
	@Published private(set) var isParsing = false

	func update(diff: String) async {
		isParsing = true
		document = .empty
		sideBySideRows = []
		defer { isParsing = false }
		let result = await Task.detached(priority: .userInitiated) {
			let document = DiffDocument(
				lines: DiffParser.parse(diff).filter { $0.kind != .metadata }
			)
			return (document, DiffSideBySideBuilder.build(from: document))
		}.value
		guard !Task.isCancelled else { return }
		document = result.0
		sideBySideRows = result.1
	}
}
