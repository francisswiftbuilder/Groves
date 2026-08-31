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
		defer {
			if activeRequestID == requestID {
				activeRequestID = nil
				isParsing = false
			}
		}
		let parseTask = Task.detached(priority: .userInitiated) {
			let document = DiffDocument(
				lines: try DiffParser.parseCancellable(diff).filter { $0.kind != .metadata }
			)
			return (document, try DiffSideBySideBuilder.buildCancellable(from: document))
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
