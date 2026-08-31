import Combine
import Foundation

@MainActor
final class DiffViewerViewModel: ObservableObject {
	struct Input: Hashable {
		let sourceID: String?
		let diff: String
	}

	@Published private(set) var document = DiffDocument.empty
	@Published private(set) var sideBySideRows: [DiffSideBySideRow] = []
	@Published private(set) var isParsing = false
	@Published private(set) var parsedInput: Input?

	private var activeRequestID: Int?
	private var requestSequence = 0

	func hasParsed(_ input: Input) -> Bool {
		parsedInput == input
	}

	func update(diff: String) async {
		await update(input: Input(sourceID: nil, diff: diff))
	}

	func update(input: Input) async {
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
				lines: try DiffParser.parseCancellable(input.diff).filter { $0.kind != .metadata }
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
		parsedInput = input
	}
}
