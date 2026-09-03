import Combine
import Foundation

@MainActor
final class DiffViewerViewModel: ObservableObject {
	struct Input: Hashable {
		let sourceID: String?
		let filePath: String?
		let diff: String

		init(sourceID: String?, filePath: String? = nil, diff: String) {
			self.sourceID = sourceID
			self.filePath = filePath ?? sourceID
			self.diff = diff
		}
	}

	struct Presentation: Equatable {
		let revision: Int
		let input: Input
		let document: DiffDocument
		let sideBySideRows: [DiffSideBySideRow]
	}

	@Published private(set) var presentation: Presentation?
	@Published private(set) var isParsing = false

	private var activeRequestID: Int?
	private var requestSequence = 0

	func hasParsed(_ input: Input) -> Bool {
		presentation?.input == input
	}

	func canInteract(with input: Input) -> Bool {
		presentation?.input == input
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
			return Presentation(
				revision: requestID,
				input: input,
				document: document,
				sideBySideRows: try DiffSideBySideBuilder.buildCancellable(from: document)
			)
		}
		let result = try? await withTaskCancellationHandler {
			try await parseTask.value
		} onCancel: {
			parseTask.cancel()
		}
		guard let result, activeRequestID == requestID else { return }
		presentation = result
	}
}
