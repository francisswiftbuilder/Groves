import Combine
import CoreGitCredential
import Foundation

@MainActor
final class GitAccountViewModel: ObservableObject {
	@Published var token = ""
	@Published var identity = GitIdentityConfiguration()
	@Published private(set) var account: GitCredentialDescriptor?
	@Published private(set) var isConnecting = false
	@Published private(set) var errorMessage: String?
	@Published private(set) var statusMessage: String?
	@Published private(set) var hasCompletedSetup: Bool
	private let store: GitCredentialStore
	private let client: GitHubAuthenticationClient
	private let defaults: UserDefaults
	private let configurationURL: URL
	private var connectionTask: Task<Void, Never>?
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
		do {
			account = try store.descriptors().first { $0.kind == .https && $0.host == "github.com" }
			errorMessage = nil
		} catch {
			statusMessage = nil
			errorMessage = error.localizedDescription
		}
	}

	func connect() {
		guard !isConnecting else { return }
		let submittedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
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
				if let account, account.account != user.login {
					errorMessage = "Sign out of the current account before connecting a different account."
					return
				}
				let descriptor = GitCredentialDescriptor(
					kind: .https, host: "github.com", account: user.login)
				try store.save(secret: submittedToken, for: descriptor)
				account = descriptor
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

	func signOut() {
		guard !isConnecting, let account else { return }
		clearMessages()
		do {
			try store.delete(account)
			self.account = nil
			token = ""
			errorMessage = nil
			statusMessage = "Signed out of Groves. Already running Git operations may still finish."
		} catch {
			errorMessage = error.localizedDescription
		}
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
