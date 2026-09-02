import AppKit
import Combine
import DomainGitInterface
import Foundation

@MainActor
final class ImageDiffViewModel: ObservableObject {
	struct Dependencies {
		let decode: @MainActor (Data?) async -> NSImage?

		init(decode: @escaping @MainActor (Data?) async -> NSImage?) {
			self.decode = decode
		}
	}

	struct Presentation {
		let beforeImage: NSImage?
		let afterImage: NSImage?
		let beforeDecodingFailed: Bool
		let afterDecodingFailed: Bool
	}

	enum State {
		case idle
		case loading
		case loaded(Presentation)
	}

	@Published private(set) var state: State = .idle

	private let dependencies: Dependencies
	private var displayedDiff: GitImageDiff?
	private var requestedDiff: GitImageDiff?
	private var requestSequence = 0
	private var loadTask: Task<Void, Never>?

	init(dependencies: Dependencies) {
		self.dependencies = dependencies
	}

	deinit {
		loadTask?.cancel()
	}

	func onAppear(diff: GitImageDiff) {
		requestPresentation(for: diff)
	}

	func onDisappear() {
		loadTask?.cancel()
		loadTask = nil
		requestedDiff = nil
		if case .loading = state {
			state = .idle
		}
	}

	func didChangeDiff(_ diff: GitImageDiff) {
		requestPresentation(for: diff)
	}

	private func requestPresentation(for diff: GitImageDiff) {
		guard displayedDiff != diff, requestedDiff != diff else { return }
		loadTask?.cancel()
		requestedDiff = diff
		requestSequence += 1
		let requestID = requestSequence
		state = .loading
		loadTask = Task {
			async let requestedBeforeImage = dependencies.decode(diff.before)
			async let requestedAfterImage = dependencies.decode(diff.after)
			let beforeImage = await requestedBeforeImage
			let afterImage = await requestedAfterImage
			guard !Task.isCancelled, requestID == requestSequence, requestedDiff == diff else {
				return
			}
			displayedDiff = diff
			requestedDiff = nil
			loadTask = nil
			state = .loaded(
				Presentation(
					beforeImage: beforeImage,
					afterImage: afterImage,
					beforeDecodingFailed: diff.before != nil && beforeImage == nil,
					afterDecodingFailed: diff.after != nil && afterImage == nil
				)
			)
		}
	}
}
