import Foundation
import Security
import Synchronization
import Testing

@testable import CoreGitCredential
@testable import Pluminon

@MainActor
struct GitAccountViewModelTests {
	private final class Context {
		let viewModel: GitAccountViewModel
		let store: GitCredentialStore
		let defaults: UserDefaults
		let configurationURL: URL
		private let identifier: String

		init(
			viewModel: GitAccountViewModel,
			store: GitCredentialStore,
			defaults: UserDefaults,
			configurationURL: URL,
			identifier: String
		) {
			self.viewModel = viewModel
			self.store = store
			self.defaults = defaults
			self.configurationURL = configurationURL
			self.identifier = identifier
		}

		deinit {
			UserDefaults(suiteName: identifier)?.removePersistentDomain(forName: identifier)
			try? FileManager.default.removeItem(at: configurationURL.deletingLastPathComponent())
		}
	}

	final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
		private static let cacheTestRepositoryRequests = Mutex(0)
		private static let rateLimitTestRequests = Mutex(0)

		static var repositoryRequestCount: Int {
			cacheTestRepositoryRequests.withLock { $0 }
		}

		override class func canInit(with request: URLRequest) -> Bool { true }
		override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

		override func startLoading() {
			let authorization = request.value(forHTTPHeaderField: "Authorization")
			if authorization == "Bearer slow-test-token" { return }
			let login = authorization == "Bearer different-test-token" ? "different" : "octocat"
			var status = authorization == "Bearer invalid-test-token" ? 401 : 200
			if request.url?.path == "/user/repos", authorization == "Bearer cache-rate-limit-token" {
				status = Self.rateLimitTestRequests.withLock {
					$0 += 1
					return $0 == 1 ? 200 : 429
				}
			}
			let response = HTTPURLResponse(
				url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
			let body: String
			switch request.url?.path {
			case "/user/repos":
				if authorization == "Bearer cache-test-token" {
					Self.cacheTestRepositoryRequests.withLock { $0 += 1 }
				}
				body =
					#"[{"id":42,"full_name":"\#(login)/ios-project","description":"iOS application","default_branch":"main","private":true,"archived":false}]"#
			case "/repos/\(login)/ios-project/contents":
				body = """
					[
						{"name":"Sources","path":"Sources","type":"dir","html_url":"https://github.com/\(login)/ios-project/tree/main/Sources"},
						{"name":"README.md","path":"README.md","type":"file","html_url":"https://github.com/\(login)/ios-project/blob/main/README.md"}
					]
					"""
			case "/repos/\(login)/ios-project/readme":
				body =
					"# iOS Project\n\nA native app with **SwiftUI** views.\n\n## Getting Started\nOpen Package.swift in Xcode."
			default:
				body = #"{"login":"\#(login)","id":42,"name":"Test User","email":null}"#
			}
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: Data(body.utf8))
			client?.urlProtocolDidFinishLoading(self)
		}

		override func stopLoading() {}
	}

	final class SecurityClientStub: GitCredentialSecurityClient, @unchecked Sendable {
		private let lock = NSLock()
		private var records: [[String: Any]] = []

		func add(_ attributes: [String: Any]) -> OSStatus {
			lock.withLock {
				records.append(attributes)
				return errSecSuccess
			}
		}

		func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
			lock.withLock {
				guard let index = records.firstIndex(where: { matches($0, query: query) }) else {
					return errSecItemNotFound
				}
				records[index].merge(attributes) { _, new in new }
				return errSecSuccess
			}
		}

		func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
			lock.withLock {
				let matchingRecords = records.filter { matches($0, query: query) }
				guard !matchingRecords.isEmpty else { return (errSecItemNotFound, nil) }
				if query[kSecReturnData as String] as? Bool == true {
					return (errSecSuccess, matchingRecords[0][kSecValueData as String])
				}
				return (errSecSuccess, matchingRecords)
			}
		}

		func delete(_ query: [String: Any]) -> OSStatus {
			lock.withLock {
				records.removeAll { matches($0, query: query) }
				return errSecSuccess
			}
		}

		private func matches(_ record: [String: Any], query: [String: Any]) -> Bool {
			let keys = [
				kSecClass, kSecAttrService, kSecAttrAccount,
				kSecUseDataProtectionKeychain, kSecAttrAccessGroup,
			]
			return keys.allSatisfy { key in
				let key = key as String
				if key == kSecAttrAccount as String, query[key] == nil { return true }
				return String(describing: record[key]) == String(describing: query[key])
			}
		}
	}

	@Test
	func testVerifiedAccountIsSavedWithoutPersistingTheTokenInDefaults() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = " valid-test-token "

		viewModel.connect()
		#expect(viewModel.token == "")
		try await waitUntil { !viewModel.isConnecting }

		let account = try #require(viewModel.account)
		#expect(account.account == "octocat")
		#expect(try context.store.secret(for: account) == "valid-test-token")
		#expect(viewModel.identity.email == "42+octocat@users.noreply.github.com")
		#expect(viewModel.errorMessage == nil)
		#expect(
			!(context.defaults.dictionaryRepresentation().values.contains {
				($0 as? String) == "valid-test-token"
			}))
	}

	@Test
	func testFailedTokenReplacementKeepsTheVerifiedAccountAndToken() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let account = try #require(viewModel.account)

		viewModel.token = "invalid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }

		#expect(viewModel.account == account)
		#expect(try context.store.secret(for: account) == "valid-test-token")
		#expect(viewModel.errorMessage != nil)
		#expect(viewModel.statusMessage == nil)
	}

	@Test
	func testReplacingATokenCannotChangeTheAccount() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let account = try #require(viewModel.account)

		viewModel.beginReplacingToken()
		viewModel.token = "different-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }

		#expect(try context.store.descriptors() == [account])
		#expect(try context.store.secret(for: account) == "valid-test-token")
		#expect(viewModel.errorMessage != nil)
		#expect(viewModel.tokenEntry == .replaceToken(account))
	}

	@Test
	func addingAndSwitchingAccountsPreservesBothTokensAndTheCommitIdentity() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let original = try #require(viewModel.account)
		let identity = viewModel.identity

		viewModel.beginAddingAccount()
		viewModel.token = "different-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let added = try #require(viewModel.account)

		#expect(added.account == "different")
		#expect(Set(viewModel.accounts) == [original, added])
		#expect(try context.store.secret(for: original) == "valid-test-token")
		#expect(try context.store.secret(for: added) == "different-test-token")
		#expect(viewModel.tokenEntry == nil)
		#expect(GitHubAccountSelection(defaults: context.defaults).account == added.account)

		viewModel.switchAccount(to: original)

		#expect(viewModel.account == original)
		#expect(viewModel.identity == identity)
		#expect(GitHubAccountSelection(defaults: context.defaults).account == original.account)
		let reloaded = GitAccountViewModel(
			store: context.store, defaults: context.defaults, configurationURL: context.configurationURL)
		reloaded.load()
		#expect(reloaded.account == original)
		#expect(Set(reloaded.accounts) == [original, added])
	}

	@Test
	func repositoryDiscoveryUsesOnlyTheActiveAccountsStoredToken() async throws {
		let context = try makeContext()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "octocat")
		let second = GitCredentialDescriptor(kind: .https, host: "github.com", account: "different")
		try context.store.save(secret: "valid-test-token", for: first)
		try context.store.save(secret: "different-test-token", for: second)
		let viewModel = context.viewModel
		viewModel.switchAccount(to: first)
		let firstList = try await viewModel.loadRepositories(for: first)
		#expect(firstList.map(\.fullName) == ["octocat/ios-project"])

		viewModel.switchAccount(to: second)
		#expect(viewModel.accessibleRepositories == nil)
		await #expect(throws: CancellationError.self) {
			_ = try await viewModel.loadRepositories(for: first)
		}
		let secondList = try await viewModel.loadRepositories(for: second)
		#expect(secondList.map(\.fullName) == ["different/ios-project"])
	}

	@Test
	func repositoryDiscoveryReusesRequestsAndRefreshesOnDemand() async throws {
		let context = try makeContext()
		let account = GitCredentialDescriptor(kind: .https, host: "github.com", account: "octocat")
		try context.store.save(secret: "cache-test-token", for: account)
		let viewModel = context.viewModel
		viewModel.switchAccount(to: account)
		let previousRequests = AuthenticationURLProtocol.repositoryRequestCount

		async let first = viewModel.loadRepositories(for: account)
		async let second = viewModel.loadRepositories(for: account)
		let (firstList, secondList) = try await (first, second)
		#expect(firstList == secondList)
		#expect(try await viewModel.loadRepositories(for: account) == firstList)
		#expect(AuthenticationURLProtocol.repositoryRequestCount == previousRequests + 1)

		#expect(try await viewModel.loadRepositories(for: account, forceRefresh: true) == firstList)
		#expect(AuthenticationURLProtocol.repositoryRequestCount == previousRequests + 2)
	}

	@Test
	func repositoryDiscoveryKeepsCachedResultsWhenARefreshIsRateLimited() async throws {
		let context = try makeContext()
		let account = GitCredentialDescriptor(kind: .https, host: "github.com", account: "octocat")
		try context.store.save(secret: "cache-rate-limit-token", for: account)
		let viewModel = context.viewModel
		viewModel.switchAccount(to: account)
		let repositories = try await viewModel.loadRepositories(for: account)

		await #expect(throws: GitHubAuthenticationError.rateLimited) {
			_ = try await viewModel.loadRepositories(for: account, forceRefresh: true)
		}
		#expect(viewModel.accessibleRepositories == repositories)
		#expect(
			viewModel.repositoryLoadError == GitHubAuthenticationError.rateLimited.localizedDescription)
	}

	@Test
	func addingAnExistingAccountCannotReplaceItsTokenOrChangeTheSelection() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let original = try #require(viewModel.account)

		viewModel.beginAddingAccount()
		viewModel.token = "another-valid-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }

		#expect(viewModel.account == original)
		#expect(viewModel.accounts == [original])
		#expect(try context.store.secret(for: original) == "valid-test-token")
		#expect(viewModel.errorMessage?.contains("already connected") == true)
		#expect(viewModel.tokenEntry == .addAccount)
	}

	@Test
	func loadingDoesNotSilentlyChooseBetweenAccountsOrReplaceAMissingSelection() throws {
		let context = try makeContext()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "first")
		let second = GitCredentialDescriptor(kind: .https, host: "github.com", account: "second")
		try context.store.save(secret: "first-token", for: first)
		try context.store.save(secret: "second-token", for: second)
		let selection = GitHubAccountSelection(defaults: context.defaults)

		context.viewModel.load()
		#expect(context.viewModel.account == nil)
		#expect(context.viewModel.accounts == [first, second])
		#expect(selection.account == nil)

		selection.select("removed-account")
		context.viewModel.load()
		#expect(context.viewModel.account == nil)
		#expect(selection.account == "removed-account")
		context.viewModel.switchAccount(to: second)
		#expect(context.viewModel.account == second)
		#expect(selection.account == "second")
	}

	@Test
	func loadingASingleLegacyAccountMakesItActive() throws {
		let context = try makeContext()
		let account = GitCredentialDescriptor(kind: .https, host: "github.com", account: "legacy")
		try context.store.save(secret: "legacy-token", for: account)

		context.viewModel.load()

		#expect(context.viewModel.account == account)
		#expect(context.viewModel.tokenEntry == nil)
		#expect(GitHubAccountSelection(defaults: context.defaults).account == "legacy")
	}

	@Test
	func signingOutRemovesOnlyTheActiveAccountAndSelectsARemainingAccount() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let original = try #require(viewModel.account)
		viewModel.beginAddingAccount()
		viewModel.token = "different-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let added = try #require(viewModel.account)

		viewModel.signOut()

		#expect(viewModel.account == original)
		#expect(viewModel.accounts == [original])
		#expect(try context.store.secret(for: original) == "valid-test-token")
		#expect(try context.store.secret(for: added) == nil)
		#expect(GitHubAccountSelection(defaults: context.defaults).account == original.account)
	}

	@Test
	func aPendingSignOutCannotRemoveAnAccountSelectedAfterTheConfirmationOpened() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let original = try #require(viewModel.account)
		viewModel.beginAddingAccount()
		viewModel.token = "different-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let added = try #require(viewModel.account)
		viewModel.beginSignOut()
		#expect(viewModel.pendingSignOut == added)

		viewModel.switchAccount(to: original)
		viewModel.confirmSignOut()

		#expect(viewModel.pendingSignOut == nil)
		#expect(viewModel.account == original)
		#expect(try context.store.secret(for: original) == "valid-test-token")
		#expect(try context.store.secret(for: added) == "different-test-token")
		viewModel.beginSignOut()
		viewModel.confirmSignOut()
		#expect(viewModel.account == added)
		#expect(try context.store.secret(for: original) == nil)
		#expect(try context.store.secret(for: added) == "different-test-token")
	}

	@Test
	func cancellingTokenEntryClearsTheDraftAndKeepsTheAccount() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let original = try #require(viewModel.account)
		viewModel.beginAddingAccount()
		viewModel.token = "slow-test-token"
		viewModel.connect()

		viewModel.cancelTokenEntry()
		viewModel.beginReplacingToken()
		viewModel.token = "draft-token"
		viewModel.cancelTokenEntry()

		#expect(!viewModel.isConnecting)
		#expect(viewModel.account == original)
		#expect(viewModel.token.isEmpty)
		#expect(viewModel.tokenEntry == nil)
		#expect(try context.store.secret(for: original) == "valid-test-token")
	}

	@Test
	func anUnavailableAccountCannotBecomeActive() throws {
		let context = try makeContext()
		let account = GitCredentialDescriptor(kind: .https, host: "github.com", account: "removed")

		context.viewModel.switchAccount(to: account)

		#expect(context.viewModel.account == nil)
		#expect(context.viewModel.errorMessage != nil)
		#expect(GitHubAccountSelection(defaults: context.defaults).account == nil)
	}

	@Test
	func testCancellationAllowsImmediateRetryWithoutPublishingAnOldError() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "slow-test-token"
		viewModel.connect()
		try await Task.sleep(for: .milliseconds(30))

		viewModel.cancelConnection()
		#expect(!(viewModel.isConnecting))
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }

		#expect(viewModel.account?.account == "octocat")
		#expect(viewModel.errorMessage == nil)
		#expect(viewModel.statusMessage?.contains("verified") == true)
	}

	@Test
	func testReleasingTheViewModelCancelsItsConnection() async throws {
		var context: Context? = try makeContext()
		context?.viewModel.token = "slow-test-token"
		context?.viewModel.connect()
		try await Task.sleep(for: .milliseconds(30))
		weak let viewModel = context?.viewModel

		context = nil

		#expect(viewModel == nil)
	}

	@Test
	func testIdentitySaveNormalizesValuesAndSignOutKeepsTheIdentity() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		viewModel.identity = GitIdentityConfiguration(name: " Author ", email: " author@example.com ")

		viewModel.saveIdentity()
		let configuration = try String(contentsOf: context.configurationURL, encoding: .utf8)
		viewModel.signOut()

		#expect(viewModel.identity.name == "Author")
		#expect(context.defaults.string(forKey: "isolatedGitAuthorEmail") == "author@example.com")
		#expect(viewModel.hasCompletedSetup)
		#expect(viewModel.account == nil)
		#expect(try context.store.descriptors().isEmpty)
		#expect(try String(contentsOf: context.configurationURL, encoding: .utf8) == configuration)
	}

	@Test
	func identityChangesCanBeSavedOrRevertedWithoutChangingTheAccount() throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		#expect(!viewModel.canSaveIdentity)
		viewModel.identity = .init(name: "Developer", email: "developer@example.com")
		#expect(viewModel.hasIdentityChanges)
		#expect(viewModel.canSaveIdentity)
		viewModel.saveIdentity()
		#expect(!viewModel.hasIdentityChanges)
		#expect(!viewModel.canSaveIdentity)
		let saved = try String(contentsOf: context.configurationURL, encoding: .utf8)
		viewModel.identity.name = "Draft"
		viewModel.restoreIdentity()
		#expect(viewModel.identity.name == "Developer")
		#expect(!viewModel.hasIdentityChanges)
		#expect(try String(contentsOf: context.configurationURL, encoding: .utf8) == saved)
		viewModel.identity.email = "invalid"
		#expect(viewModel.hasIdentityChanges)
		#expect(!viewModel.canSaveIdentity)
	}

	@Test
	func testFailedIdentitySaveDoesNotCompleteOnboarding() throws {
		let context = try makeContext()
		try FileManager.default.createDirectory(
			at: context.configurationURL, withIntermediateDirectories: true)
		context.viewModel.identity = GitIdentityConfiguration(
			name: "Author", email: "author@example.com")

		context.viewModel.saveIdentity()

		#expect(!(context.viewModel.hasCompletedSetup))
		#expect(!(context.defaults.bool(forKey: "isolatedGitSetupCompleted")))
		#expect(context.viewModel.errorMessage != nil)
		#expect(context.viewModel.identityErrorMessage != nil)
		#expect(context.viewModel.hasIdentityChanges)
		#expect(context.viewModel.statusMessage == nil)
	}

	private func makeContext() throws -> Context {
		let identifier = "Pluminon.Account.Tests.\(UUID().uuidString)"
		let directoryURL = FileManager.default.temporaryDirectory.appending(path: identifier)
		let configurationURL = directoryURL.appending(path: "config")
		let defaults = try #require(UserDefaults(suiteName: identifier))
		let store = GitCredentialStore(
			service: identifier,
			securityClient: SecurityClientStub(),
			accessGroupResolver: { "TESTTEAM.Pluminon.Account.Tests" }
		)
		let sessionConfiguration = URLSessionConfiguration.ephemeral
		sessionConfiguration.protocolClasses = [AuthenticationURLProtocol.self]
		let client = GitHubAuthenticationClient(
			session: URLSession(configuration: sessionConfiguration))
		return Context(
			viewModel: GitAccountViewModel(
				store: store, client: client, defaults: defaults, configurationURL: configurationURL),
			store: store,
			defaults: defaults,
			configurationURL: configurationURL,
			identifier: identifier
		)
	}

	private func waitUntil(_ condition: () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for account verification")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
