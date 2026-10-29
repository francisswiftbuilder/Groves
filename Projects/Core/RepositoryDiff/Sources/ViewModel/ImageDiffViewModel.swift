import AppKit
import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
final class ImageDiffViewModel {
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

	private(set) var state: State = .idle

	private let dependencies: Dependencies
	private var displayedDiff: GitImageDiff?
	private var requestSequence = 0

	init(dependencies: Dependencies) {
		self.dependencies = dependencies
	}

	func update(diff: GitImageDiff) async {
		if displayedDiff == diff, case .loaded = state { return }
		requestSequence += 1
		let requestID = requestSequence
		state = .loading
		async let requestedBeforeImage = dependencies.decode(diff.before)
		async let requestedAfterImage = dependencies.decode(diff.after)
		let beforeImage = await requestedBeforeImage
		let afterImage = await requestedAfterImage
		guard requestID == requestSequence else { return }
		guard !Task.isCancelled else {
			if case .loading = state { state = .idle }
			return
		}
		displayedDiff = diff
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
