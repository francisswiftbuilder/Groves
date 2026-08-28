import Foundation

public struct GitCredentialHelper: Sendable {
	private let store: GitCredentialStore
	private let decisionStore: GitCredentialSaveDecisionStore

	public init(
		store: GitCredentialStore = GitCredentialStore(),
		decisionStore: GitCredentialSaveDecisionStore = GitCredentialSaveDecisionStore()
	) {
		self.store = store
		self.decisionStore = decisionStore
	}

	public func handle(
		operation: GitCredentialHelperOperation,
		input: String,
		operationID: String?
	) throws -> String? {
		let fields = Self.fields(in: input)
		guard fields["protocol"] == "https" || fields["protocol"] == "http",
			let host = fields["host"]
		else { return nil }

		switch operation {
		case .get:
			return try respondToGet(host: host, username: fields["username"])
		case .store:
			try storeCredential(
				host: host,
				username: fields["username"],
				password: fields["password"],
				operationID: operationID
			)
			return nil
		case .erase:
			try eraseCredentials(host: host, username: fields["username"])
			return nil
		}
	}

	private func respondToGet(host: String, username: String?) throws -> String? {
		let descriptor: GitCredentialDescriptor?
		if let username {
			descriptor = GitCredentialDescriptor(kind: .https, host: host, account: username)
		} else {
			descriptor = try store.descriptors().first { $0.kind == .https && $0.host == host }
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
