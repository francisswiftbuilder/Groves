import Foundation
import XCTest

@testable import DataGit

final class GitSSHTrustScopeTests: XCTestCase {
	func testTrustScopeCopiesKnownHostsWithoutMutatingTheUserFile() throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let userKnownHostsURL = directoryURL.appending(path: "known_hosts")
		let existingEntry = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexisting\n"
		try Data(existingEntry.utf8).write(to: userKnownHostsURL)

		let scope = try GitSSHTrustScope(userKnownHostsURL: userKnownHostsURL)
		defer { scope.remove() }

		XCTAssertNotEqual(scope.knownHostsURL, userKnownHostsURL)
		XCTAssertEqual(
			try String(contentsOf: scope.knownHostsURL, encoding: .utf8),
			existingEntry,
			"Already trusted hosts must still verify against the copy"
		)

		let trustedOnce = existingEntry + "example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAtrusted\n"
		try Data(trustedOnce.utf8).write(to: scope.knownHostsURL)

		XCTAssertEqual(
			try String(contentsOf: userKnownHostsURL, encoding: .utf8),
			existingEntry,
			"Trusting a host once must not change the user's known_hosts"
		)
	}

	func testTrustScopeIsRemovedAfterTheOperation() throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let scope = try GitSSHTrustScope(
			userKnownHostsURL: directoryURL.appending(path: "missing_known_hosts")
		)

		XCTAssertTrue(FileManager.default.fileExists(atPath: scope.knownHostsURL.path))
		let attributes = try FileManager.default.attributesOfItem(atPath: scope.knownHostsURL.path)
		XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

		scope.remove()

		XCTAssertFalse(FileManager.default.fileExists(atPath: scope.knownHostsURL.path))
	}

	func testTrustScopeKeepsHostKeyCheckingInteractive() throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let scope = try GitSSHTrustScope(
			userKnownHostsURL: directoryURL.appending(path: "known_hosts")
		)
		defer { scope.remove() }

		let options = scope.sshOptions.joined(separator: " ")

		XCTAssertTrue(options.contains("StrictHostKeyChecking=ask"))
		XCTAssertTrue(options.contains(scope.knownHostsURL.path))
		XCTAssertFalse(options.contains("StrictHostKeyChecking=no"))
	}
}
