import Combine
import Foundation

@MainActor
public final class RepositorySearchViewModel: ObservableObject, RepositoryFindActions {
	@Published public var query = "" {
		didSet {
			guard query != oldValue else { return }
			requestSearch(preservingCurrentMatch: false)
		}
	}
	@Published public var isPresented = false
	@Published private(set) var matches: [RepositorySearchMatch] = []
	@Published private(set) var currentIndex: Int?

	private var sources: [RepositorySearchSource] = []
	private var searchTask: Task<Void, Never>?

	public init() {}

	deinit {
		searchTask?.cancel()
	}

	var currentMatch: RepositorySearchMatch? {
		guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
		return matches[currentIndex]
	}

	var currentMatchID: String? {
		currentMatch?.id
	}

	var statusText: String {
		guard !matches.isEmpty, let currentIndex else { return "0 of 0" }
		return "\(currentIndex + 1) of \(matches.count)"
	}

	public func update(sources: [RepositorySearchSource]) {
		guard self.sources != sources else { return }
		self.sources = sources
		requestSearch(preservingCurrentMatch: true)
	}

	public func present() {
		isPresented = true
	}

	public func next() {
		guard !matches.isEmpty else {
			present()
			return
		}
		currentIndex = ((currentIndex ?? -1) + 1) % matches.count
	}

	public func previous() {
		guard !matches.isEmpty else {
			present()
			return
		}
		currentIndex = ((currentIndex ?? 0) - 1 + matches.count) % matches.count
	}

	func activeRange(for sourceID: Int) -> DiffTextRange? {
		guard let currentMatch, currentMatch.sourceID == sourceID else { return nil }
		return DiffTextRange(location: currentMatch.location, length: currentMatch.length)
	}

	private func requestSearch(preservingCurrentMatch: Bool) {
		searchTask?.cancel()
		let query = query
		let sources = sources
		let previousMatch = preservingCurrentMatch ? currentMatch : nil
		guard !query.isEmpty else {
			matches = []
			currentIndex = nil
			return
		}

		searchTask = Task {
			let matches = await Task.detached(priority: .userInitiated) {
				Self.findMatches(query: query, sources: sources)
			}.value
			guard !Task.isCancelled, self.query == query, self.sources == sources else { return }
			self.matches = matches
			if let previousMatch, let index = matches.firstIndex(of: previousMatch) {
				self.currentIndex = index
			} else {
				self.currentIndex = matches.isEmpty ? nil : 0
			}
		}
	}

	nonisolated private static func findMatches(
		query: String,
		sources: [RepositorySearchSource]
	) -> [RepositorySearchMatch] {
		var result: [RepositorySearchMatch] = []
		for source in sources {
			var searchRange = source.text.startIndex..<source.text.endIndex
			while let range = source.text.range(
				of: query,
				options: [.caseInsensitive, .diacriticInsensitive],
				range: searchRange
			) {
				let location = source.text.distance(
					from: source.text.startIndex,
					to: range.lowerBound
				)
				let length = source.text.distance(from: range.lowerBound, to: range.upperBound)
				result.append(
					RepositorySearchMatch(
						sourceID: source.id,
						location: location,
						length: length
					)
				)
				guard range.upperBound < source.text.endIndex else { break }
				searchRange = range.upperBound..<source.text.endIndex
			}
		}
		return result
	}
}
