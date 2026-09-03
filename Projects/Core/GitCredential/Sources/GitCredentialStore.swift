import Foundation
import Security

public final class GitCredentialStore: GitCredentialPersisting, Sendable {
	private enum Storage {
		case current
		case legacy
	}

	private struct StoredItem {
		let account: String
		let descriptor: GitCredentialDescriptor
		let creationDate: Date?
		let updatedAt: Date?
	}

	private static let accessGroupSuffix = "io.github.francisswiftbuilder.Groves.GitCredential"
	private static let stalePendingAge: TimeInterval = 24 * 60 * 60

	private let service: String
	private let pendingService: String
	private let securityClient: any GitCredentialSecurityClient
	private let accessGroupResolver: @Sendable () throws -> String
	private let now: @Sendable () -> Date
	private let diagnosticHandler: @Sendable (GitCredentialStoreError) -> Void

	public convenience init(service: String = "io.github.francisswiftbuilder.Groves.GitCredential") {
		self.init(
			service: service,
			securityClient: SystemGitCredentialSecurityClient(),
			accessGroupResolver: Self.signedAccessGroup,
			now: Date.init,
			diagnosticHandler: { _ in }
		)
	}

	init(
		service: String,
		securityClient: any GitCredentialSecurityClient,
		accessGroupResolver: @escaping @Sendable () throws -> String,
		now: @escaping @Sendable () -> Date = Date.init,
		diagnosticHandler: @escaping @Sendable (GitCredentialStoreError) -> Void = { _ in }
	) {
		self.service = service
		pendingService = service + ".pending"
		self.securityClient = securityClient
		self.accessGroupResolver = accessGroupResolver
		self.now = now
		self.diagnosticHandler = diagnosticHandler
	}

	public func descriptors() throws -> [GitCredentialDescriptor] {
		let currentItems = try items(service: service, storage: .current)
		let legacyItems = try items(service: service, storage: .legacy)
		return Dictionary(
			(currentItems + legacyItems).map { ($0.descriptor.id, $0.descriptor) },
			uniquingKeysWith: { current, _ in current }
		)
		.values
		.sorted {
			if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
			if $0.host != $1.host {
				return $0.host.localizedStandardCompare($1.host) == .orderedAscending
			}
			return $0.account.localizedStandardCompare($1.account) == .orderedAscending
		}
	}

	public func secret(for descriptor: GitCredentialDescriptor) throws -> String? {
		if let secret = try secret(account: descriptor.id, service: service, storage: .current) {
			return secret
		}
		guard let secret = try secret(account: descriptor.id, service: service, storage: .legacy)
		else { return nil }
		try migrate(secret: secret, descriptor: descriptor)
		return secret
	}

	public func save(secret: String, for descriptor: GitCredentialDescriptor) throws {
		try save(
			secret: secret,
			descriptor: descriptor,
			account: descriptor.id,
			service: service,
			storage: .current
		)
	}

	public func delete(_ descriptor: GitCredentialDescriptor) throws {
		for storage in [Storage.current, .legacy] {
			try delete(account: descriptor.id, service: service, storage: storage)
		}
	}

	public func deleteAll() throws {
		for storage in [Storage.current, .legacy] {
			try deleteAll(service: service, storage: storage)
			try deleteAll(service: pendingService, storage: storage)
		}
	}

	public func savePending(
		secret: String,
		for descriptor: GitCredentialDescriptor,
		operationID: String
	) throws {
		pruneStalePending(excluding: operationID)
		try save(
			secret: secret,
			descriptor: descriptor,
			account: pendingAccount(operationID: operationID, descriptor: descriptor),
			service: pendingService,
			storage: .current
		)
	}

	public func commitPending(operationID: String) throws {
		pruneStalePending(excluding: operationID)
		let pendingItems = try items(service: pendingService, storage: .current)
			.filter { $0.account.hasPrefix(operationID + "|") }
		let resolvedItems = try pendingItems.map { item in
			guard
				let secret = try secret(
					account: item.account,
					service: pendingService,
					storage: .current
				)
			else {
				throw GitCredentialStoreError.missingPendingSecret
			}
			return (item, secret)
		}
		for (item, secret) in resolvedItems {
			try save(secret: secret, for: item.descriptor)
		}
		for (item, _) in resolvedItems {
			try delete(account: item.account, service: pendingService, storage: .current)
		}
	}

	public func discardPending(operationID: String) throws {
		pruneStalePending(excluding: operationID)
		for storage in [Storage.current, .legacy] {
			for item in try items(service: pendingService, storage: storage)
			where item.account.hasPrefix(operationID + "|") {
				try delete(account: item.account, service: pendingService, storage: storage)
			}
		}
	}

	private func migrate(secret: String, descriptor: GitCredentialDescriptor) throws {
		try save(secret: secret, for: descriptor)
		guard try self.secret(account: descriptor.id, service: service, storage: .current) != nil else {
			throw GitCredentialStoreError.migrationVerificationFailed
		}
		try delete(account: descriptor.id, service: service, storage: .legacy)
	}

	private func save(
		secret: String,
		descriptor: GitCredentialDescriptor,
		account: String,
		service: String,
		storage: Storage
	) throws {
		let label = try JSONEncoder().encode(descriptor).base64EncodedString()
		var query = try baseQuery(service: service, storage: storage)
		query[kSecAttrAccount as String] = account
		let attributes: [String: Any] = [
			kSecValueData as String: Data(secret.utf8),
			kSecAttrLabel as String: label,
			kSecAttrComment as String: String(now().timeIntervalSince1970),
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
		]
		let updateStatus = securityClient.update(query: query, attributes: attributes)
		if updateStatus == errSecSuccess { return }
		guard updateStatus == errSecItemNotFound else {
			throw GitCredentialStoreError(operation: .update, status: updateStatus)
		}
		query.merge(attributes) { _, new in new }
		let addStatus = securityClient.add(query)
		guard addStatus == errSecSuccess else {
			throw GitCredentialStoreError(operation: .add, status: addStatus)
		}
	}

	private func items(service: String, storage: Storage) throws -> [StoredItem] {
		var query = try baseQuery(service: service, storage: storage)
		query[kSecReturnAttributes as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitAll
		let response = securityClient.copyMatching(query)
		if response.status == errSecItemNotFound { return [] }
		guard response.status == errSecSuccess else {
			throw GitCredentialStoreError(operation: .copyItems, status: response.status)
		}
		let rawItems: [[String: Any]]
		if let items = response.result as? [[String: Any]] {
			rawItems = items
		} else if let item = response.result as? [String: Any] {
			rawItems = [item]
		} else {
			rawItems = []
		}
		return rawItems.compactMap { item in
			guard let account = item[kSecAttrAccount as String] as? String,
				let descriptor = descriptor(from: item)
			else {
				diagnosticHandler(.invalidDescriptor)
				return nil
			}
			return StoredItem(
				account: account,
				descriptor: descriptor,
				creationDate: item[kSecAttrCreationDate as String] as? Date,
				updatedAt: (item[kSecAttrComment as String] as? String)
					.flatMap(TimeInterval.init)
					.map(Date.init(timeIntervalSince1970:))
			)
		}
	}

	private func descriptor(from item: [String: Any]) -> GitCredentialDescriptor? {
		guard let label = item[kSecAttrLabel as String] as? String,
			let data = Data(base64Encoded: label),
			let descriptor = try? JSONDecoder().decode(GitCredentialDescriptor.self, from: data)
		else { return nil }
		return descriptor
	}

	private func secret(account: String, service: String, storage: Storage) throws -> String? {
		var query = try baseQuery(service: service, storage: storage)
		query[kSecAttrAccount as String] = account
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		let response = securityClient.copyMatching(query)
		if response.status == errSecItemNotFound { return nil }
		guard response.status == errSecSuccess else {
			throw GitCredentialStoreError(operation: .copySecret, status: response.status)
		}
		guard let data = response.result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	private func delete(account: String, service: String, storage: Storage) throws {
		var query = try baseQuery(service: service, storage: storage)
		query[kSecAttrAccount as String] = account
		try delete(query)
	}

	private func deleteAll(service: String, storage: Storage) throws {
		try delete(try baseQuery(service: service, storage: storage))
	}

	private func delete(_ query: [String: Any]) throws {
		let status = securityClient.delete(query)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw GitCredentialStoreError(operation: .delete, status: status)
		}
	}

	private func baseQuery(service: String, storage: Storage) throws -> [String: Any] {
		var query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
		]
		if storage == .current, let accessGroup = try currentAccessGroup() {
			query[kSecUseDataProtectionKeychain as String] = true
			query[kSecAttrAccessGroup as String] = accessGroup
		}
		return query
	}

	private func currentAccessGroup() throws -> String? {
		do {
			return try accessGroupResolver()
		} catch GitCredentialStoreError.missingAccessGroup {
			return nil
		}
	}

	private func pruneStalePending(excluding operationID: String) {
		for storage in [Storage.current, .legacy] {
			do {
				let threshold = now().addingTimeInterval(-Self.stalePendingAge)
				for item in try items(service: pendingService, storage: storage) {
					guard item.account.hasPrefix(operationID + "|") == false else { continue }
					if let age = item.updatedAt ?? item.creationDate, age >= threshold { continue }
					try delete(account: item.account, service: pendingService, storage: storage)
				}
			} catch let error as GitCredentialStoreError {
				diagnosticHandler(error)
			} catch {
				continue
			}
		}
	}

	private func pendingAccount(
		operationID: String,
		descriptor: GitCredentialDescriptor
	) -> String {
		"\(operationID)|\(descriptor.id)"
	}

	private static func signedAccessGroup() throws -> String {
		guard let task = SecTaskCreateFromSelf(nil),
			let groups = SecTaskCopyValueForEntitlement(
				task,
				"keychain-access-groups" as CFString,
				nil
			) as? [String],
			let group = groups.first(where: {
				$0 == accessGroupSuffix || $0.hasSuffix("." + accessGroupSuffix)
			})
		else {
			throw GitCredentialStoreError.missingAccessGroup
		}
		return group
	}
}
