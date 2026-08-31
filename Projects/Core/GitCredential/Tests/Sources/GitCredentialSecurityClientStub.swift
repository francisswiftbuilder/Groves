import Foundation
import Security

@testable import CoreGitCredential

final class GitCredentialSecurityClientStub: GitCredentialSecurityClient, @unchecked Sendable {
	enum Call {
		case add([String: Any])
		case update(query: [String: Any], attributes: [String: Any])
		case copyMatching([String: Any])
		case delete([String: Any])
	}

	private let lock = NSLock()
	private var records: [[String: Any]] = []
	private var calls: [Call] = []
	var nextAddStatus: OSStatus?
	var nextUpdateStatus: OSStatus?
	var nextCopyStatus: OSStatus?
	var nextDeleteStatus: OSStatus?

	var recordedCalls: [Call] {
		lock.withLock { calls }
	}

	func insert(
		secret: String?,
		descriptor: GitCredentialDescriptor,
		account: String? = nil,
		service: String,
		storageIsCurrent: Bool,
		creationDate: Date? = Date(),
		updatedAt: Date? = nil
	) throws {
		let label = try JSONEncoder().encode(descriptor).base64EncodedString()
		lock.withLock {
			var record: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account ?? descriptor.id,
				kSecAttrLabel as String: label,
			]
			if let secret {
				record[kSecValueData as String] = Data(secret.utf8)
			}
			if let creationDate {
				record[kSecAttrCreationDate as String] = creationDate
			}
			if let updatedAt {
				record[kSecAttrComment as String] = String(updatedAt.timeIntervalSince1970)
			}
			addStorageAttributes(to: &record, storageIsCurrent: storageIsCurrent)
			records.append(record)
		}
	}

	func insertMalformed(
		account: String,
		service: String,
		storageIsCurrent: Bool
	) {
		lock.withLock {
			var record: [String: Any] = [
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account,
				kSecAttrLabel as String: "not-a-descriptor",
			]
			addStorageAttributes(to: &record, storageIsCurrent: storageIsCurrent)
			records.append(record)
		}
	}

	func contains(account: String, service: String, storageIsCurrent: Bool) -> Bool {
		lock.withLock {
			records.contains { record in
				guard record[kSecAttrAccount as String] as? String == account,
					record[kSecAttrService as String] as? String == service
				else { return false }
				return (record[kSecUseDataProtectionKeychain as String] != nil) == storageIsCurrent
			}
		}
	}

	func add(_ attributes: [String: Any]) -> OSStatus {
		lock.withLock {
			calls.append(.add(attributes))
			if let status = nextAddStatus {
				nextAddStatus = nil
				return status
			}
			guard matchingIndexes(for: attributes).isEmpty else { return errSecDuplicateItem }
			var record = attributes
			record[kSecAttrCreationDate as String] = Date()
			records.append(record)
			return errSecSuccess
		}
	}

	func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
		lock.withLock {
			calls.append(.update(query: query, attributes: attributes))
			if let status = nextUpdateStatus {
				nextUpdateStatus = nil
				return status
			}
			let indexes = matchingIndexes(for: query)
			guard indexes.isEmpty == false else { return errSecItemNotFound }
			for index in indexes {
				records[index].merge(attributes) { _, new in new }
			}
			return errSecSuccess
		}
	}

	func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
		lock.withLock {
			calls.append(.copyMatching(query))
			if let status = nextCopyStatus {
				nextCopyStatus = nil
				return (status, nil)
			}
			let matches = matchingIndexes(for: query).map { records[$0] }
			guard matches.isEmpty == false else { return (errSecItemNotFound, nil) }
			if query[kSecReturnData as String] as? Bool == true {
				return (errSecSuccess, matches[0][kSecValueData as String])
			}
			if query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String {
				return (errSecSuccess, matches[0])
			}
			return (errSecSuccess, matches)
		}
	}

	func delete(_ query: [String: Any]) -> OSStatus {
		lock.withLock {
			calls.append(.delete(query))
			if let status = nextDeleteStatus {
				nextDeleteStatus = nil
				return status
			}
			let indexes = matchingIndexes(for: query)
			guard indexes.isEmpty == false else { return errSecItemNotFound }
			for index in indexes.reversed() {
				records.remove(at: index)
			}
			return errSecSuccess
		}
	}

	private func addStorageAttributes(
		to record: inout [String: Any],
		storageIsCurrent: Bool
	) {
		guard storageIsCurrent else { return }
		record[kSecUseDataProtectionKeychain as String] = true
		record[kSecAttrAccessGroup as String] =
			"TESTTEAM.io.github.francisswiftbuilder.Trees.GitCredential"
	}

	private func matchingIndexes(for query: [String: Any]) -> [Int] {
		records.indices.filter { index in
			let record = records[index]
			return matches(kSecClass, query: query, record: record)
				&& matches(kSecAttrService, query: query, record: record)
				&& matches(kSecAttrAccount, query: query, record: record)
				&& matchesStorage(kSecUseDataProtectionKeychain, query: query, record: record)
				&& matchesStorage(kSecAttrAccessGroup, query: query, record: record)
		}
	}

	private func matches(
		_ key: CFString,
		query: [String: Any],
		record: [String: Any]
	) -> Bool {
		let key = key as String
		guard let expected = query[key] else { return true }
		guard let actual = record[key] else { return false }
		return String(describing: actual) == String(describing: expected)
	}

	private func matchesStorage(
		_ key: CFString,
		query: [String: Any],
		record: [String: Any]
	) -> Bool {
		let key = key as String
		guard let expected = query[key] else { return record[key] == nil }
		guard let actual = record[key] else { return false }
		return String(describing: actual) == String(describing: expected)
	}
}

func makeTestCredentialStore(
	service: String = "Trees.Tests.\(UUID().uuidString)",
	securityClient: GitCredentialSecurityClientStub = GitCredentialSecurityClientStub(),
	now: @escaping @Sendable () -> Date = Date.init,
	diagnosticHandler: @escaping @Sendable (GitCredentialStoreError) -> Void = { _ in }
) -> GitCredentialStore {
	GitCredentialStore(
		service: service,
		securityClient: securityClient,
		accessGroupResolver: { "TESTTEAM.io.github.francisswiftbuilder.Trees.GitCredential" },
		now: now,
		diagnosticHandler: diagnosticHandler
	)
}
