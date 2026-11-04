import DomainGitInterface
import Foundation
import FoundationModels
import Testing

@testable import DataGit

struct OnDeviceCommitAnalyzerTests {
	private actor Recorder {
		var prompts: [String] = []
		var shouldFail = true

		func summarize(_ prompt: String) throws -> String {
			prompts.append(prompt)
			if shouldFail, prompts.count == 2 {
				shouldFail = false
				throw URLError(.networkConnectionLost)
			}
			return "Update greeting behavior."
		}
	}

	@Test
	func largeUnicodeChangesKeepTheirOriginalPatchesAndIDs() async throws {
		let analyzer = makeAnalyzer()
		let patch = String(repeating: "+안녕하세요 🌳 greeting\n", count: 500)
		let chunks = try await analyzer.split(patch, path: "Greeting.swift")
		#expect(chunks.count > 1)
		#expect(chunks.joined() == patch)
		let input = input(patch: patch)
		let result = try await analyzer.analyze(input)
		#expect(result.isValid)
		#expect(result.input == input)
		#expect(result.tasks.flatMap(\.unitIDs) == ["original"])
	}

	@Test
	func aLongSingleLineIsSplitWithoutDroppingContent() async throws {
		let text = String(repeating: "🌳가", count: 2_000)
		let chunks = try await makeAnalyzer().split(text, path: "Long.swift")
		#expect(chunks.count > 1)
		#expect(chunks.joined() == text)
	}

	@Test
	func retryReusesSuccessfulChunkSummaries() async throws {
		let recorder = Recorder()
		let cache = CommitAnalysisCache()
		let analyzer = makeAnalyzer(cache: cache, summarize: { try await recorder.summarize($0) })
		let input = input(patch: (0..<300).map { "+unique change \($0)\n" }.joined())
		await #expect(throws: URLError.self) { try await analyzer.analyze(input) }
		let first = try #require(await recorder.prompts.first)
		let result = try await analyzer.analyze(input)
		#expect(result.isValid)
		let prompts = await recorder.prompts
		#expect(prompts.filter { $0 == first }.count == 1)
	}

	@Test
	func cancellationStopsBeforeSummarizing() async throws {
		let analyzer = makeAnalyzer()
		let input = input(patch: String(repeating: "+change\n", count: 1_000))
		let task = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return try await analyzer.analyze(input)
		}
		await #expect(throws: CancellationError.self) { try await task.value }
	}

	@Test
	func smallBlocksAreGroupedWithoutIndividualSummaryRequests() async throws {
		let units = (0..<17).map { index in
			GitCommitUnit(
				id: "unit-\(index)", path: "File\(index).swift", patch: "+@MainActor", hunk: nil)
		}
		let input = GitCommitPlanInput(headHash: "head", indexFingerprint: "index", units: units)
		let analyzer = OnDeviceCommitAnalyzer(
			summarize: { _ in throw URLError(.badServerResponse) },
			generate: { prompt in
				let ids = prompt.split(separator: "\n").compactMap { line -> Int? in
					guard line.hasPrefix("CHANGE ") else { return nil }
					return Int(line.dropFirst(7))
				}
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix: isolate UI updates", body: "", changeIDs: ids)
				])
			}, fits: { $0.utf8.count <= 1_000 }, cache: CommitAnalysisCache(), progress: { _ in })
		let plan = try await analyzer.analyze(input)
		#expect(plan.isValid)
		#expect(plan.input == input)
		#expect(plan.tasks.count == 1)
	}

	@Test
	func summariesAcrossBatchesPreserveEveryOriginalChange() async throws {
		let units = (0..<17).map { index in
			GitCommitUnit(id: "unit-\(index)", path: "File\(index).swift", patch: "+change", hunk: nil)
		}
		let input = GitCommitPlanInput(headHash: "head", indexFingerprint: "index", units: units)
		let analyzer = OnDeviceCommitAnalyzer(
			summarize: { _ in "Update a related helper." },
			generate: { prompt in
				let ids = prompt.split(separator: "\n").compactMap { line -> Int? in
					guard line.hasPrefix("CHANGE ") else { return nil }
					return Int(line.dropFirst(7))
				}
				return GeneratedCommitPlan(commits: [
					.init(
						subject: "refactor: update helpers", body: "Related helper updates.", changeIDs: ids)
				])
			},
			fits: { $0.utf8.count <= 1_000 }, cache: CommitAnalysisCache(), progress: { _ in })
		let result = try await analyzer.analyze(input)
		#expect(result.isValid)
		#expect(result.tasks.count == 1)
		#expect(Set(result.tasks.flatMap(\.unitIDs)) == Set(units.map(\.id)))
		#expect(result.input == input)
	}

	private func makeAnalyzer(
		cache: CommitAnalysisCache = CommitAnalysisCache(),
		summarize: @escaping @Sendable (String) async throws -> String = { prompt in
			#expect(prompt.utf8.count <= 1_000)
			return "Update greeting behavior."
		}
	) -> OnDeviceCommitAnalyzer {
		OnDeviceCommitAnalyzer(
			summarize: summarize,
			generate: { prompt in
				#expect(prompt.utf8.count <= 1_000)
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix: update greeting", body: "", changeIDs: [0])
				])
			},
			fits: { $0.utf8.count <= 1_000 }, cache: cache, progress: { _ in })
	}

	@Test
	func invalidGroupAssignmentsAreRetriedInSmallerGroups() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index",
			units: [
				.init(id: "first", path: "First.swift", patch: "+first", hunk: nil),
				.init(id: "second", path: "Second.swift", patch: "+second", hunk: nil),
			])
		let analyzer = OnDeviceCommitAnalyzer(
			summarize: { _ in "Update helper." },
			generate: { prompt in
				let invalid = prompt.contains("CHANGE 1\n")
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix: update helper", body: "", changeIDs: invalid ? [0, 0] : [0])
				])
			},
			fits: { _ in true }, cache: CommitAnalysisCache(), progress: { _ in })
		let result = try await analyzer.analyze(input)
		#expect(result.isValid)
		#expect(Set(result.tasks.flatMap(\.unitIDs)) == ["first", "second"])
	}

	private func input(patch: String) -> GitCommitPlanInput {
		.init(
			headHash: "head", indexFingerprint: "index",
			units: [
				.init(id: "original", path: "Greeting.swift", patch: patch, hunk: nil)
			])
	}

	@Test
	@available(macOS 27.0, *)
	func truncatedStructuredResponsesFallBackToSmallerGroups() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index",
			units: [
				.init(id: "first", path: "First.swift", patch: "+first", hunk: nil),
				.init(id: "second", path: "Second.swift", patch: "+second", hunk: nil),
			])
		let analyzer = OnDeviceCommitAnalyzer(
			summarize: { _ in "Update helper." },
			generate: { prompt in
				if prompt.contains("CHANGE 1\n") {
					let partial = try GeneratedContent(
						json: #"{"subject":"fix: update helper","body":"Partial response"}"#)
					return GeneratedCommitPlan(commits: [try GeneratedCommitPlan.Commit(partial)])
				}
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix: update helper", body: "", changeIDs: [0])
				])
			},
			fits: { _ in true }, cache: CommitAnalysisCache(), progress: { _ in })
		let result = try await analyzer.analyze(input)
		#expect(result.isValid)
		#expect(Set(result.tasks.flatMap(\.unitIDs)) == ["first", "second"])
	}
}
