import Combine
import Foundation

@MainActor
final class DiffViewerViewModel: ObservableObject {
	@Published private(set) var document = DiffDocument.empty
	@Published private(set) var sideBySideRows: [DiffSideBySideRow] = []
	@Published private(set) var isParsing = false

	private var activeRequestID: Int?
	private var requestSequence = 0

	func update(diff: String) async {
		requestSequence += 1
		let requestID = requestSequence
		activeRequestID = requestID
		isParsing = true
		document = .empty
		sideBySideRows = []
		defer {
			if activeRequestID == requestID {
				activeRequestID = nil
				isParsing = false
			}
		}
		let parseTask = Task.detached(priority: .userInitiated) {
			try Task.checkCancellation()
			let document = DiffDocument(
				lines: DiffParser.parse(diff).filter { $0.kind != .metadata }
			)
			try Task.checkCancellation()
			return (document, DiffSideBySideBuilder.build(from: document))
		}
		let result = try? await withTaskCancellationHandler {
			try await parseTask.value
		} onCancel: {
			parseTask.cancel()
		}
		guard let result, activeRequestID == requestID else { return }
		document = result.0
		sideBySideRows = result.1
	}
}
