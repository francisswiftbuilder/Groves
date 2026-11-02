import Darwin
import Foundation
import Security

enum GitCredentialPeerVerification {
	static func hasExpectedCode(_ peer: GitCredentialSocket.Peer, at url: URL) -> Bool {
		guard peer.userIdentifier == geteuid() else { return false }
		var expectedCode: SecStaticCode?
		var requirement: SecRequirement?
		var runningCode: SecCode?
		let attributes = [kSecGuestAttributeAudit as String: peer.auditToken] as CFDictionary
		guard SecStaticCodeCreateWithPath(url as CFURL, [], &expectedCode) == errSecSuccess,
			let expectedCode,
			SecStaticCodeCheckValidity(
				expectedCode, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil) == errSecSuccess,
			SecCodeCopyDesignatedRequirement(expectedCode, [], &requirement) == errSecSuccess,
			let requirement,
			SecCodeCopyGuestWithAttributes(nil, attributes, [], &runningCode) == errSecSuccess,
			let runningCode
		else { return false }
		return SecCodeCheckValidity(runningCode, [], requirement) == errSecSuccess
	}

	static func isDescendant(_ processIdentifier: Int32, of ancestor: Int32) -> Bool {
		var current = processIdentifier
		var visited: Set<Int32> = []
		while current > 1, visited.count < 64, visited.insert(current).inserted {
			var info = proc_bsdinfo()
			let size = Int32(MemoryLayout.size(ofValue: info))
			guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
			current = Int32(info.pbi_ppid)
			if current == ancestor { return true }
		}
		return false
	}

	static func parentApplicationURL(for helperBundleURL: URL) throws -> URL {
		let helpers = helperBundleURL.deletingLastPathComponent()
		let contents = helpers.deletingLastPathComponent()
		let app = contents.deletingLastPathComponent()
		guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
			app.pathExtension == "app"
		else { throw GitCredentialBrokerError.untrustedPeer }
		return app
	}
}
