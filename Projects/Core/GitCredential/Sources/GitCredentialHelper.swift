import Foundation

public struct GitCredentialHelper: Sendable {
	private enum GitHubAccount {
		case automatic
		case selected(String)
		case unconnected
		case selectionRequired
	}

	private let store: GitCredentialStore
	private let decisionStore: GitCredentialSaveDecisionStore
	private var gitHubAccount = GitHubAccount.automatic

	public init(
		store: GitCredentialStore = GitCredentialStore(),
		decisionStore: GitCredentialSaveDecisionStore = GitCredentialSaveDecisionStore()
	) {
		self.store = store
		self.decisionStore = decisionStore
	}

	public func selectingGitHubAccount(_ account: String?) throws -> GitCredentialHelper {
		var helper = self
		if let account {
			helper.gitHubAccount = .selected(account)
		} else {
			let accounts = try store.descriptors().filter { $0.kind == .https && $0.host == "github.com" }
			if accounts.count == 1, let account = accounts.first {
				helper.gitHubAccount = .selected(account.account)
			} else {
				helper.gitHubAccount = accounts.isEmpty ? .unconnected : .selectionRequired
			}
		}
		return helper
	}

	public func handle(
		operation: GitCredentialHelperOperation,
		input: String,
		operationID: String?
	) throws -> String? {
		let fields = Self.fields(in: input)
		guard fields["protocol"] == "https",
			let rawHost = fields["host"], !rawHost.isEmpty
		else { return nil }
		let host =
			["github.com", "github.com:443"].contains(rawHost.lowercased()) ? "github.com" : rawHost
		let selectedAccount = try selectedGitHubAccount(for: host)
		if host == "github.com", case .unconnected = gitHubAccount {
			if operation == .erase { return nil }
			throw GitHubAccountSelectionError.selectionRequired
		}

		switch operation {
		case .get:
			if let selectedAccount {
				let descriptor = GitCredentialDescriptor(kind: .https, host: host, account: selectedAccount)
				guard let secret = try store.secret(for: descriptor) else {
					throw GitHubAccountSelectionError.accountUnavailable
				}
				return Self.response(["username": selectedAccount, "password": secret])
			}
			return try respondToGet(host: host, username: fields["username"])
		case .store:
			if let selectedAccount, fields["username"] != selectedAccount {
				throw GitHubAccountSelectionError.accountMismatch
			}
			try storeCredential(
				host: host,
				username: fields["username"],
				password: fields["password"],
				operationID: operationID
			)
			return nil
		case .erase:
			if host == "github.com", selectedAccount == nil,
				fields["username"]?.isEmpty != false,
				try store.descriptors().filter({ $0.kind == .https && $0.host == host }).count > 1
			{
				throw GitHubAccountSelectionError.selectionRequired
			}
			try eraseCredentials(host: host, username: selectedAccount ?? fields["username"])
			return nil
		}
	}

	private func selectedGitHubAccount(for host: String) throws -> String? {
		guard host == "github.com" else { return nil }
		switch gitHubAccount {
		case .automatic, .unconnected: return nil
		case .selected(let account): return account
		case .selectionRequired: throw GitHubAccountSelectionError.selectionRequired
		}
	}

	public func setShouldSave(_ shouldSave: Bool, operationID: String) {
		decisionStore.setShouldSave(shouldSave, operationID: operationID)
	}

	public static func supports(input: String) -> Bool {
		let fields = fields(in: input)
		return fields["protocol"] == "https" && fields["host"]?.isEmpty == false
	}

	private func respondToGet(host: String, username: String?) throws -> String? {
		let descriptor: GitCredentialDescriptor?
		if let username, !username.isEmpty {
			descriptor = GitCredentialDescriptor(kind: .https, host: host, account: username)
		} else {
			let accounts = try store.descriptors().filter { $0.kind == .https && $0.host == host }
			guard host != "github.com" || accounts.count <= 1 else {
				throw GitHubAccountSelectionError.selectionRequired
			}
			descriptor = accounts.first
		}
		guard let descriptor, let secret = try store.secret(for: descriptor) else { return nil }
		return Self.response(["username": descriptor.account, "password": secret])
	}

	private func storeCredential(
		host: String,
		username: String?,
		password: String?,
		operationID: String?
	) throws {
		guard let username,
			let password,
			let operationID,
			!operationID.isEmpty,
			decisionStore.consumeShouldSave(operationID: operationID)
		else { return }
		try store.savePending(
			secret: password,
			for: GitCredentialDescriptor(kind: .https, host: host, account: username),
			operationID: operationID
		)
	}

	private func eraseCredentials(host: String, username: String?) throws {
		for descriptor in try store.descriptors()
		where descriptor.kind == .https
			&& descriptor.host == host
			&& (username == nil || descriptor.account == username)
		{
			try store.delete(descriptor)
		}
	}

	private static func fields(in input: String) -> [String: String] {
		var fields: [String: String] = [:]
		for line: Substring in input.split(whereSeparator: \.isNewline) {
			guard let separator = line.firstIndex(of: "=") else { continue }
			let key = String(line[line.startIndex..<separator])
			let value = String(line[line.index(after: separator)...])
			fields[key] = value
		}
		return fields
	}

	private static func response(_ fields: [String: String]) -> String {
		fields.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: "\n") + "\n\n"
	}
}
