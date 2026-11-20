import CoreGitCredential
import Foundation
import Observation

@MainActor
@Observable
final class GitAccountViewModel {
	enum TokenEntry: Equatable {
		case addAccount
		case replaceToken(GitCredentialDescriptor)
	}

	var token = ""
	var identity = GitIdentityConfiguration()
	private(set) var account: GitCredentialDescriptor? {
		didSet {
			if account != oldValue { invalidateRepositoryAccess() }
		}
	}
	private(set) var repositoryAccessRevision = 0
	private(set) var accessibleRepositories: [GitHubRepository]?
	private(set) var repositoryLoadError: String?
	private(set) var isLoadingRepositories = false
	private(set) var accounts: [GitCredentialDescriptor] = []
	private(set) var tokenEntry: TokenEntry?
	private(set) var pendingSignOut: GitCredentialDescriptor?
	private(set) var isConnecting = false
	private(set) var errorMessage: String?
	private(set) var identityErrorMessage: String?
	private(set) var statusMessage: String?
	private(set) var hasCompletedSetup: Bool
	private var savedIdentity = GitIdentityConfiguration()
	private let store: GitCredentialStore
	private let client: GitHubAuthenticationClient
	private let defaults: UserDefaults
	private let configurationURL: URL
	private let accountSelection: GitHubAccountSelection
	@ObservationIgnored private var connectionTask: Task<Void, Never>?
	@ObservationIgnored private var repositoryLoadTask: Task<[GitHubRepository], any Error>?
	private var repositoriesUpdatedAt: ContinuousClock.Instant?
	private var activeConnectionRequestID: Int?
	private var connectionRequestSequence = 0

	init(
		store: GitCredentialStore = GitCredentialStore(),
		client: GitHubAuthenticationClient = GitHubAuthenticationClient(),
		defaults: UserDefaults = .standard,
		configurationURL: URL = GitIdentityConfiguration.defaultURL
	) {
		self.store = store
		self.client = client
		self.defaults = defaults
		self.configurationURL = configurationURL
		accountSelection = GitHubAccountSelection(defaults: defaults)
		hasCompletedSetup = defaults.bool(forKey: "isolatedGitSetupCompleted")
		identity = GitIdentityConfiguration(
			name: defaults.string(forKey: "isolatedGitAuthorName") ?? "",
			email: defaults.string(forKey: "isolatedGitAuthorEmail") ?? ""
		)
		savedIdentity = identity
	}

	var hasIdentityChanges: Bool { identity != savedIdentity }
	var canSaveIdentity: Bool { identity.isValid && hasIdentityChanges && !isConnecting }

	deinit {
		connectionTask?.cancel()
		repositoryLoadTask?.cancel()
	}

	func load() {
		guard !isConnecting else { return }
		do {
			let accounts = try savedAccounts()
			self.accounts = accounts
			if let selected = accountSelection.account {
				account = accounts.first { $0.account == selected }
			} else if accounts.count == 1 {
				account = accounts.first
				accountSelection.select(account?.account)
			} else {
				account = nil
			}
			if pendingSignOut != account { pendingSignOut = nil }
			errorMessage = nil
		} catch {
			statusMessage = nil
			errorMessage = error.localizedDescription
		}
	}

	func loadRepositories(for account: GitCredentialDescriptor, forceRefresh: Bool = false)
		async throws -> [GitHubRepository]
	{
		guard self.account == account else { throw CancellationError() }
		try Task.checkCancellation()
		if repositoryLoadTask == nil, !forceRefresh, let accessibleRepositories,
			let repositoriesUpdatedAt,
			ContinuousClock.now - repositoriesUpdatedAt < .seconds(60)
		{
			return accessibleRepositories
		}
		let revision = repositoryAccessRevision
		let task = repositoryLoadTask ?? startRepositoryLoad(for: account, revision: revision)
		let repositories = try await task.value
		try Task.checkCancellation()
		guard repositoryAccessRevision == revision else { throw CancellationError() }
		return repositories
	}

	private func startRepositoryLoad(for account: GitCredentialDescriptor, revision: Int)
		-> Task<[GitHubRepository], any Error>
	{
		let showsPartialResults = accessibleRepositories == nil
		repositoryLoadError = nil
		isLoadingRepositories = true
		let task = Task { [weak self, store, client] in
			defer {
				if let self, repositoryAccessRevision == revision {
					repositoryLoadTask = nil
					isLoadingRepositories = false
				}
			}
			do {
				guard let token = try store.secret(for: account) else {
					throw GitHubAccountSelectionError.accountUnavailable
				}
				let repositories = try await client.repositories(token: token) { [weak self] partial in
					guard showsPartialResults else { return }
					await self?.publishRepositories(partial, revision: revision)
				}
				try Task.checkCancellation()
				guard let self, repositoryAccessRevision == revision else { throw CancellationError() }
				publishRepositories(repositories, revision: revision)
				repositoriesUpdatedAt = .now
				return accessibleRepositories ?? []
			} catch {
				if let self, repositoryAccessRevision == revision, !Task.isCancelled {
					repositoryLoadError = error.localizedDescription
					repositoriesUpdatedAt = nil
					let authenticationError = error as? GitHubAuthenticationError
					if authenticationError == .invalidToken || authenticationError == .forbidden
						|| error is GitHubAccountSelectionError
					{
						accessibleRepositories = nil
					}
				}
				throw error
			}
		}
		repositoryLoadTask = task
		return task
	}

	private func publishRepositories(_ repositories: [GitHubRepository], revision: Int) {
		guard revision == repositoryAccessRevision else { return }
		accessibleRepositories = repositories.sorted {
			$0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
		}
	}

	private func invalidateRepositoryAccess() {
		repositoryAccessRevision += 1
		repositoryLoadTask?.cancel()
		repositoryLoadTask = nil
		accessibleRepositories = nil
		repositoryLoadError = nil
		repositoriesUpdatedAt = nil
		isLoadingRepositories = false
	}

	func loadRepositoryFiles(
		for repository: GitHubRepository, account: GitCredentialDescriptor
	) async throws -> [GitHubRepositoryFile] {
		try await loadRepositorySection(for: account) { token in
			try await client.repositoryFiles(for: repository, token: token)
		}
	}

	func loadRepositoryReadme(
		for repository: GitHubRepository, account: GitCredentialDescriptor
	) async throws -> GitHubRepositoryReadme {
		try await loadRepositorySection(for: account) { token in
			try await client.repositoryReadme(for: repository, token: token)
		}
	}

	private func loadRepositorySection<Value>(
		for account: GitCredentialDescriptor, load: (String) async throws -> Value
	) async throws -> Value {
		guard self.account == account else { throw CancellationError() }
		let revision = repositoryAccessRevision
		guard let token = try store.secret(for: account) else {
			throw GitHubAccountSelectionError.accountUnavailable
		}
		let value = try await load(token)
		try Task.checkCancellation()
		guard revision == repositoryAccessRevision else { throw CancellationError() }
		return value
	}

	func beginAddingAccount() {
		guard !isConnecting else { return }
		token = ""
		clearMessages()
		tokenEntry = .addAccount
		pendingSignOut = nil
	}

	func beginReplacingToken() {
		guard !isConnecting, let account else { return }
		token = ""
		clearMessages()
		tokenEntry = .replaceToken(account)
		pendingSignOut = nil
	}

	func cancelTokenEntry() {
		cancelConnection()
		token = ""
		tokenEntry = nil
		clearMessages()
	}

	func switchAccount(to account: GitCredentialDescriptor) {
		guard !isConnecting else { return }
		clearMessages()
		do {
			let accounts = try savedAccounts()
			guard accounts.contains(account) else { throw GitHubAccountSelectionError.accountUnavailable }
			self.accounts = accounts
			self.account = account
			accountSelection.select(account.account)
			token = ""
			tokenEntry = nil
			pendingSignOut = nil
			statusMessage = "Using \(account.account) for new GitHub operations."
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func connect() {
		guard !isConnecting else { return }
		let submittedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !submittedToken.isEmpty else { return }
		let entry = tokenEntry ?? account.map(TokenEntry.replaceToken) ?? .addAccount
		pendingSignOut = nil
		token = ""
		clearMessages()
		connectionRequestSequence += 1
		let requestID = connectionRequestSequence
		activeConnectionRequestID = requestID
		isConnecting = true
		let client = client
		connectionTask = Task { [weak self] in
			defer { self?.finishConnection(id: requestID) }
			do {
				try Task.checkCancellation()
				let user = try await client.account(token: submittedToken)
				try Task.checkCancellation()
				guard let self, self.activeConnectionRequestID == requestID else { return }
				if case .replaceToken(let account) = entry, account.account != user.login {
					errorMessage =
						"This token belongs to a different GitHub account. Use Add Account to connect it."
					return
				}
				let descriptor = GitCredentialDescriptor(
					kind: .https, host: "github.com", account: user.login)
				let accounts = try savedAccounts()
				if entry == .addAccount, accounts.contains(descriptor) {
					errorMessage =
						"This GitHub account is already connected. Select it and choose Replace Token."
					return
				}
				try store.save(secret: submittedToken, for: descriptor)
				if account == descriptor { invalidateRepositoryAccess() }
				self.accounts = (accounts.filter { $0 != descriptor } + [descriptor]).sorted {
					$0.account.localizedStandardCompare($1.account) == .orderedAscending
				}
				account = descriptor
				accountSelection.select(descriptor.account)
				tokenEntry = nil
				if identity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					identity.name = name.isEmpty ? user.login : name
				}
				if identity.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					identity.email = user.commitEmail
				}
				statusMessage = "Account verified. Repository access depends on the token’s permissions."
			} catch is CancellationError {
				return
			} catch {
				guard let self, !Task.isCancelled, self.activeConnectionRequestID == requestID else {
					return
				}
				errorMessage = error.localizedDescription
			}
		}
	}

	func cancelConnection() {
		token = ""
		guard activeConnectionRequestID != nil else { return }
		activeConnectionRequestID = nil
		connectionTask?.cancel()
		connectionTask = nil
		isConnecting = false
		errorMessage = nil
		statusMessage = "Connection cancelled."
	}

	func saveIdentity() {
		guard !isConnecting else { return }
		clearMessages()
		do {
			let savedIdentity = GitIdentityConfiguration(
				name: identity.name.trimmingCharacters(in: .whitespacesAndNewlines),
				email: identity.email.trimmingCharacters(in: .whitespacesAndNewlines)
			)
			try savedIdentity.save(to: configurationURL)
			identity = savedIdentity
			self.savedIdentity = savedIdentity
			defaults.set(identity.name, forKey: "isolatedGitAuthorName")
			defaults.set(identity.email, forKey: "isolatedGitAuthorEmail")
			defaults.set(true, forKey: "isolatedGitSetupCompleted")
			hasCompletedSetup = true
			errorMessage = nil
			statusMessage = "Git identity saved for Pluminon."
		} catch {
			errorMessage = error.localizedDescription
			identityErrorMessage = error.localizedDescription
		}
	}

	func continueLocally() {
		guard !isConnecting else { return }
		clearMessages()
		defaults.set(true, forKey: "isolatedGitSetupCompleted")
		hasCompletedSetup = true
	}

	func restoreIdentity() {
		guard !isConnecting else { return }
		identity = savedIdentity
		clearMessages()
	}

	func beginSignOut() {
		guard !isConnecting else { return }
		pendingSignOut = account
	}

	func cancelSignOut() {
		pendingSignOut = nil
	}

	func confirmSignOut() {
		guard let pendingSignOut, pendingSignOut == account else { return }
		self.pendingSignOut = nil
		signOut()
	}

	func signOut() {
		guard !isConnecting, let account else { return }
		clearMessages()
		do {
			let remainingAccounts = try savedAccounts().filter { $0 != account }
			try store.delete(account)
			accounts = remainingAccounts
			self.account = accounts.first
			accountSelection.select(self.account?.account)
			token = ""
			tokenEntry = nil
			pendingSignOut = nil
			errorMessage = nil
			if let account = self.account {
				statusMessage = "Signed out. Using \(account.account) for new GitHub operations."
			} else {
				statusMessage = "Signed out of Pluminon. Already running Git operations may still finish."
			}
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func savedAccounts() throws -> [GitCredentialDescriptor] {
		try store.descriptors().filter { $0.kind == .https && $0.host == "github.com" }
	}

	private func finishConnection(id: Int) {
		guard activeConnectionRequestID == id else { return }
		activeConnectionRequestID = nil
		connectionTask = nil
		isConnecting = false
	}

	private func clearMessages() {
		errorMessage = nil
		identityErrorMessage = nil
		statusMessage = nil
	}
}
