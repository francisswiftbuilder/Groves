import Foundation
import Security
import Testing

@testable import CoreGitCredential
@testable import Groves

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

	private final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
		override class func canInit(with request: URLRequest) -> Bool { true }
		override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

		override func startLoading() {
			let authorization = request.value(forHTTPHeaderField: "Authorization")
			if authorization == "Bearer slow-test-token" { return }
			let login = authorization == "Bearer different-test-token" ? "different" : "octocat"
			let status = authorization == "Bearer invalid-test-token" ? 401 : 200
			let response = HTTPURLResponse(
				url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
			let data = Data(
				"{\"login\":\"\(login)\",\"id\":42,\"name\":\"Test User\",\"email\":null}".utf8)
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: data)
			client?.urlProtocolDidFinishLoading(self)
		}

		override func stopLoading() {}
	}

	private final class SecurityClientStub: GitCredentialSecurityClient, @unchecked Sendable {
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
	func testDifferentAccountRequiresSigningOutBeforeReplacingTheToken() async throws {
		let context = try makeContext()
		let viewModel = context.viewModel
		viewModel.token = "valid-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }
		let account = try #require(viewModel.account)

		viewModel.token = "different-test-token"
		viewModel.connect()
		try await waitUntil { !viewModel.isConnecting }

		#expect(try context.store.descriptors() == [account])
		#expect(try context.store.secret(for: account) == "valid-test-token")
		#expect(viewModel.errorMessage != nil)
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
		#expect(context.viewModel.statusMessage == nil)
	}

	private func makeContext() throws -> Context {
		let identifier = "Groves.Account.Tests.\(UUID().uuidString)"
		let directoryURL = FileManager.default.temporaryDirectory.appending(path: identifier)
		let configurationURL = directoryURL.appending(path: "config")
		let defaults = try #require(UserDefaults(suiteName: identifier))
		let store = GitCredentialStore(
			service: identifier,
			securityClient: SecurityClientStub(),
			accessGroupResolver: { "TESTTEAM.Groves.Account.Tests" }
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
