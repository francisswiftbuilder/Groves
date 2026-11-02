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
	private(set) var account: GitCredentialDescriptor?
	private(set) var accounts: [GitCredentialDescriptor] = []
	private(set) var tokenEntry: TokenEntry?
	private(set) var pendingSignOut: GitCredentialDescriptor?
	private(set) var isConnecting = false
	private(set) var errorMessage: String?
	private(set) var statusMessage: String?
	private(set) var hasCompletedSetup: Bool
	private let store: GitCredentialStore
	private let client: GitHubAuthenticationClient
	private let defaults: UserDefaults
	private let configurationURL: URL
	private let accountSelection: GitHubAccountSelection
	@ObservationIgnored private var connectionTask: Task<Void, Never>?
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
	}

	deinit {
		connectionTask?.cancel()
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
			defaults.set(identity.name, forKey: "isolatedGitAuthorName")
			defaults.set(identity.email, forKey: "isolatedGitAuthorEmail")
			defaults.set(true, forKey: "isolatedGitSetupCompleted")
			hasCompletedSetup = true
			errorMessage = nil
			statusMessage = "Git identity saved for Groves."
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func continueLocally() {
		guard !isConnecting else { return }
		clearMessages()
		defaults.set(true, forKey: "isolatedGitSetupCompleted")
		hasCompletedSetup = true
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
				statusMessage = "Signed out of Groves. Already running Git operations may still finish."
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
		statusMessage = nil
	}
}
