import Foundation
import Security

public final class GitCredentialStore: GitCredentialPersisting, @unchecked Sendable {
	private let service: String
	private let pendingService: String
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	public init(service: String = "io.github.francisswiftbuilder.Trees.GitCredential") {
		self.service = service
		pendingService = service + ".pending"
	}

	public func descriptors() throws -> [GitCredentialDescriptor] {
		try items(service: service)
			.compactMap { try descriptor(from: $0) }
			.sorted {
				if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
				if $0.host != $1.host {
					return $0.host.localizedStandardCompare($1.host) == .orderedAscending
				}
				return $0.account.localizedStandardCompare($1.account) == .orderedAscending
			}
	}

	public func secret(for descriptor: GitCredentialDescriptor) throws -> String? {
		if let secret = try secret(account: descriptor.id, service: service) {
			return secret
		}
		guard descriptor.id != descriptor.legacyIdentifier,
			let legacySecret = try secret(account: descriptor.legacyIdentifier, service: service)
		else { return nil }
		try save(secret: legacySecret, for: descriptor)
		try delete(account: descriptor.legacyIdentifier, service: service)
		return legacySecret
	}

	public func save(secret: String, for descriptor: GitCredentialDescriptor) throws {
		try save(
			secret: secret,
			descriptor: descriptor,
			account: descriptor.id,
			service: service
		)
	}

	public func delete(_ descriptor: GitCredentialDescriptor) throws {
		try delete(account: descriptor.id, service: service)
		guard descriptor.id != descriptor.legacyIdentifier else { return }
		try delete(account: descriptor.legacyIdentifier, service: service)
	}

	public func deleteAll() throws {
		try deleteAll(service: service)
		try deleteAll(service: pendingService)
	}

	public func savePending(
		secret: String,
		for descriptor: GitCredentialDescriptor,
		operationID: String
	) throws {
		try save(
			secret: secret,
			descriptor: descriptor,
			account: pendingAccount(operationID: operationID, descriptor: descriptor),
			service: pendingService
		)
	}

	public func commitPending(operationID: String) throws {
		for item in try items(service: pendingService) {
			guard let account = item[kSecAttrAccount as String] as? String,
				account.hasPrefix(operationID + "|"),
				let secret = try secret(account: account, service: pendingService),
				let descriptor = try descriptor(from: item)
			else { continue }
			try save(secret: secret, for: descriptor)
			try delete(account: account, service: pendingService)
		}
	}

	public func discardPending(operationID: String) throws {
		for item in try items(service: pendingService) {
			guard let account = item[kSecAttrAccount as String] as? String,
				account.hasPrefix(operationID + "|")
			else { continue }
			try delete(account: account, service: pendingService)
		}
	}

	private func save(
		secret: String,
		descriptor: GitCredentialDescriptor,
		account: String,
		service: String
	) throws {
		let label = try encoder.encode(descriptor).base64EncodedString()
		var query = baseQuery(service: service)
		query[kSecAttrAccount as String] = account
		let attributes: [String: Any] = [
			kSecValueData as String: Data(secret.utf8),
			kSecAttrLabel as String: label,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
		]
		let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		if updateStatus == errSecSuccess { return }
		guard updateStatus == errSecItemNotFound else {
			throw GitCredentialStoreError.keychain(updateStatus)
		}
		query.merge(attributes) { _, new in new }
		let addStatus = SecItemAdd(query as CFDictionary, nil)
		guard addStatus == errSecSuccess else {
			throw GitCredentialStoreError.keychain(addStatus)
		}
	}

	private func items(service: String) throws -> [[String: Any]] {
		var query = baseQuery(service: service)
		query[kSecReturnAttributes as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitAll
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		if status == errSecItemNotFound { return [] }
		guard status == errSecSuccess else { throw GitCredentialStoreError.keychain(status) }
		if let items = result as? [[String: Any]] {
			return items
		}
		if let item = result as? [String: Any] {
			return [item]
		}
		return []
	}

	private func descriptor(from item: [String: Any]) throws -> GitCredentialDescriptor? {
		guard let label = item[kSecAttrLabel as String] as? String,
			let data = Data(base64Encoded: label)
		else { return nil }
		do {
			return try decoder.decode(GitCredentialDescriptor.self, from: data)
		} catch {
			throw GitCredentialStoreError.invalidDescriptor
		}
	}

	private func secret(account: String, service: String) throws -> String? {
		var query = baseQuery(service: service)
		query[kSecAttrAccount as String] = account
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		if status == errSecItemNotFound { return nil }
		guard status == errSecSuccess else { throw GitCredentialStoreError.keychain(status) }
		guard let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	private func delete(account: String, service: String) throws {
		var query = baseQuery(service: service)
		query[kSecAttrAccount as String] = account
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw GitCredentialStoreError.keychain(status)
		}
	}

	private func deleteAll(service: String) throws {
		let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw GitCredentialStoreError.keychain(status)
		}
	}

	private func baseQuery(service: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
		]
	}

	private func pendingAccount(
		operationID: String,
		descriptor: GitCredentialDescriptor
	) -> String {
		"\(operationID)|\(descriptor.id)"
	}
}
