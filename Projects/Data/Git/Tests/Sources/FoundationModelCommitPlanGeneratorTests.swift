import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct FoundationModelCommitPlanGeneratorTests {
	private actor Calls {
		var cloud = 0
		var device = 0
		var grouping = 0

		func recordCloud() { cloud += 1 }
		func recordDevice() { device += 1 }
		func recordGrouping() { grouping += 1 }
	}

	@Test
	func availableCloudModelIsPreferred() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in
				await calls.recordCloud()
				return response()
			},
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		let plan = try await generator.generatePlan(for: input())
		#expect(plan.model == .privateCloudCompute)
		#expect(plan.isValid)
		#expect(await calls.cloud == 1)
		#expect(await calls.device == 0)
	}

	@Test(arguments: [false, true])
	func cloudUnavailabilityAndFailureFallBackOnDevice(fails: Bool) async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in
				await calls.recordCloud()
				if fails { throw URLError(.notConnectedToInternet) }
				return nil
			},
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		let plan = try await generator.generatePlan(for: input())
		#expect(plan.model == .onDevice)
		#expect(plan.isValid)
		#expect(await calls.cloud == 1)
		#expect(await calls.device == 1)
	}

	@Test
	func cancellationDoesNotStartFallback() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in throw CancellationError() },
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		await #expect(throws: CancellationError.self) {
			try await generator.generatePlan(for: input())
		}
		#expect(await calls.device == 0)
	}

	@Test(arguments: [[0, 0], [], [1], [-1]])
	func invalidModelAssignmentsAreRejected(ids: [Int]) async throws {
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				GeneratedCommitPlan(commits: [
					.init(subject: "fix: update file", body: "", changeIDs: ids)
				])
			})
		await #expect(throws: GitCommitPlanError.self) {
			try await generator.generatePlan(for: input())
		}
	}

	@Test
	func coAuthorAttributionIsRejected() async throws {
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				GeneratedCommitPlan(commits: [
					.init(subject: "fix: update file", body: "Co-Authored-By: Someone", changeIDs: [0])
				])
			})
		await #expect(throws: GitCommitPlanError.self) {
			try await generator.generatePlan(for: input())
		}
	}

	private func input() -> GitCommitPlanInput {
		GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index",
			units: [
				GitCommitUnit(id: "block", path: "file.swift", patch: "+updated", hunk: nil)
			])
	}

	@Test
	func invalidMultilineSubjectIsRetriedBeforePresentingThePlan() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				await calls.recordDevice()
				if await calls.device == 1 {
					return GeneratedCommitPlan(commits: [
						.init(subject: "fix: update file\n\nDetails", body: "", changeIDs: [0])
					])
				}
				#expect(prompt.contains("single line"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input()).isValid)
		#expect(await calls.device == 2)
	}

	@Test
	func repositoryHistoryReachesBothModelsWithoutAttribution() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: ["fix(auth): 로그인 상태 복원\n\n- 세션 복원 처리\nCo-Authored-By: Example"])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { prompt in
				#expect(prompt.contains("fix(auth): 로그인 상태 복원"))
				#expect(!prompt.contains("Co-Authored-By"))
				return nil
			},
			deviceGeneration: { prompt in
				#expect(prompt.contains("fix(auth): 로그인 상태 복원"))
				#expect(prompt.contains("Output language: Korean (ko)"))
				#expect(prompt.contains("Subject format: type(scope): description"))
				#expect(prompt.contains("style reference only"))
				#expect(!prompt.contains("Co-Authored-By"))
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix(auth): 세션 상태 갱신", body: "- 세션 갱신 처리", changeIDs: [0])
				])
			})
		let result = try await generator.generatePlan(for: input)
		#expect(result.isValid)
		#expect(result.tasks.first?.subject == "fix(auth): 세션 상태 갱신")
		#expect(result.input == input)
	}

	@Test
	func commitMetadataDoesNotOverrideTheHistoryLanguage() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: [
				"fix(greeting): 인사 문구 수정", "feat(greeting): 인사말 표시",
			])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { prompt in
				#expect(prompt.contains("Output language: Korean (ko)"))
				return nil
			},
			deviceGeneration: { prompt in
				#expect(prompt.contains("Output language: Korean (ko)"))
				#expect(prompt.contains("Subject format: type(scope): description"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input).isValid)
	}

	@Test
	func translatedConventionalTypesAreRetried() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				await calls.recordDevice()
				if await calls.device == 1 {
					return GeneratedCommitPlan(commits: [
						.init(subject: "수정: 인사 문구 변경", body: "", changeIDs: [0])
					])
				}
				#expect(prompt.contains("MUST stay in English"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input()).isValid)
		#expect(await calls.device == 2)
	}

	@Test
	func truncatedDirectGenerationFallsBackToChunkedAnalysis() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				await calls.recordDevice()
				if prompt.contains("Organize these staged change blocks") {
					throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Truncated"))
				}
				return response()
			},
			deviceSummary: { _ in "Update the file." })
		let plan = try await generator.generatePlan(for: input())
		#expect(plan.isValid)
		#expect(plan.input == input())
		#expect(await calls.device == 4)
	}

	@Test
	func failedMessageDraftReusesCompletedGrouping() async throws {
		let calls = Calls()
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index",
			units: [
				.init(
					id: "block", path: "file.swift", patch: String(repeating: "+change\n", count: 800),
					hunk: nil)
			])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				await calls.recordDevice()
				if await calls.device == 1 { throw URLError(.networkConnectionLost) }
				return response()
			}, deviceSummary: { _ in "Update the helper." }, deviceFits: { $0.utf8.count < 1_000 },
			groupGeneration: { _ in
				await calls.recordGrouping()
				return response()
			})
		await #expect(throws: URLError.self) { try await generator.generatePlan(for: input) }
		#expect(try await generator.generatePlan(for: input).isValid)
		#expect(await calls.grouping == 1)
		#expect(await calls.device == 2)
	}

	@Test
	func nonConventionalHistoryKeepsItsSubjectFormat() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: ["Update greeting text", "Add a greeting view"])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				GeneratedCommitPlan(commits: [
					.init(subject: "Update the greeting", body: "", changeIDs: [0])
				])
			})
		#expect(
			try await generator.generatePlan(for: input).tasks.first?.subject == "Update the greeting")
	}

	@Test
	func releaseVersionsAndCodeIdentifiersDoNotOverrideKoreanProse() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: [
				"fix: develop 최신 수정사항을 모듈 구조에 반영", "chore: release 3.1.7",
				"fix: 폼 요청을 multipart/form-data 대신 application/x-www-form-urlencoded 방식으로 전송하도록 변경합니다.",
				"chore: release 3.1.6",
				"fix: LaunchScreen 루트에 ignoresSafeArea를 적용해 알림 안내 팝업이 표시되지 않는 현상을 수정합니다.",
				"chore: release 3.1.5",
			])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				#expect(prompt.contains("Output language: Korean (ko)"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input).isValid)
	}

	@Test
	func technicalBodyTextDoesNotOverrideTheSubjectLanguage() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: [
				"fix: 로그인 상태 복원\n\n"
					+ String(
						repeating: "Restore the authentication state and update the session coordinator. ",
						count: 8)
			])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				#expect(prompt.contains("Output language: Korean (ko)"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input).isValid)
	}

	@Test
	func longCommitHistoryIsBoundedBeforePrompting() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: Array(repeating: String(repeating: "변경 내용\n", count: 1_000), count: 8))
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				#expect(prompt.utf8.count < 2_000)
				return response()
			})
		#expect(try await generator.generatePlan(for: input).isValid)
	}

	@Test
	func messageLocalizationPreservesThePrefixAndAssignments() async throws {
		let result = GeneratedCommitPlan(commits: [
			.init(
				subject: "fix(player)!: Restore playback state",
				body: "Keep the active track after launch.",
				changeIDs: [2, 5])
		])
		let localized = try await FoundationModelCommitPlanGenerator.localizedPlan(
			result, language: "ko"
		) {
			text in
			#expect(!text.contains("fix(player)"))
			#expect(text.contains("Keep the active track"))
			return "재생 상태 복원\n\n실행 후 활성 트랙을 유지합니다."
		}
		#expect(localized.commits.first?.subject == "fix(player)!: 재생 상태 복원")
		#expect(localized.commits.first?.body == "실행 후 활성 트랙을 유지합니다.")
		#expect(localized.commits.first?.changeIDs == [2, 5])
	}

	@Test(arguments: [nil, "ko"] as [String?])
	func messagesAlreadyUsingTheHistoryLanguageAreNotTranslated(language: String?) async throws {
		let result = GeneratedCommitPlan(commits: [
			.init(subject: "fix: 재생 상태 복원", body: "", changeIDs: [0])
		])
		let localized = try await FoundationModelCommitPlanGenerator.localizedPlan(
			result, language: language
		) {
			_ in
			throw GitCommitPlanError.invalidPlan
		}
		#expect(localized.commits.first?.subject == result.commits.first?.subject)
	}

	@Test(arguments: ["", "Restore playback state", "재생 상태 복원\n\nCo-Authored-By: Example"])
	func invalidTranslationsAreRejected(translation: String) async throws {
		await #expect(throws: GitCommitPlanError.self) {
			try await FoundationModelCommitPlanGenerator.localizedPlan(response(), language: "ko") { _ in
				translation
			}
		}
	}

	private func response() -> GeneratedCommitPlan {
		GeneratedCommitPlan(commits: [.init(subject: "fix: update file", body: "", changeIDs: [0])])
	}
}
