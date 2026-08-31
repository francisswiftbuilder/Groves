import Foundation
import Security

struct SystemGitCredentialSecurityClient: GitCredentialSecurityClient {
	func add(_ attributes: [String: Any]) -> OSStatus {
		SecItemAdd(attributes as CFDictionary, nil)
	}

	func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
		SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
	}

	func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		return (status, result)
	}

	func delete(_ query: [String: Any]) -> OSStatus {
		SecItemDelete(query as CFDictionary)
	}
}
