import Foundation
import Testing

@testable import DataGit

struct GitSSHTrustScopeTests {
	private final class TemporaryFileManager: FileManager, @unchecked Sendable {
		private let directoryURL: URL

		init(directoryURL: URL) {
			self.directoryURL = directoryURL
			super.init()
		}

		override var temporaryDirectory: URL { directoryURL }
	}

	@Test
	func testTrustScopeCopiesKnownHostsWithoutMutatingTheUserFile() throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let userKnownHostsURL = directoryURL.appending(path: "known_hosts")
		let existingEntry = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexisting\n"
		try Data(existingEntry.utf8).write(to: userKnownHostsURL)

		let scope = try GitSSHTrustScope(userKnownHostsURL: userKnownHostsURL)
		defer { scope.remove() }

		#expect(scope.knownHostsURL != userKnownHostsURL)
		#expect(
			try String(contentsOf: scope.knownHostsURL, encoding: .utf8) == existingEntry,
			"Already trusted hosts must still verify against the copy")

		let trustedOnce = existingEntry + "example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAtrusted\n"
		try Data(trustedOnce.utf8).write(to: scope.knownHostsURL)

		#expect(
			try String(contentsOf: userKnownHostsURL, encoding: .utf8) == existingEntry,
			"Trusting a host once must not change the user's known_hosts")
	}

	@Test
	func testTrustScopeIsRemovedAfterTheOperation() throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let scope = try GitSSHTrustScope(
			userKnownHostsURL: directoryURL.appending(path: "missing_known_hosts")
		)

		#expect(FileManager.default.fileExists(atPath: scope.knownHostsURL.path))
		let attributes = try FileManager.default.attributesOfItem(atPath: scope.knownHostsURL.path)
		#expect(attributes[.posixPermissions] as? Int == 0o600)

		scope.remove()

		#expect(!(FileManager.default.fileExists(atPath: scope.knownHostsURL.path)))
	}

	@Test
	func testUnreadableKnownHostsFileFailsWithoutLeavingATemporaryCopy() throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let userKnownHostsURL = directoryURL.appending(path: "known_hosts")
		try Data("github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexisting\n".utf8)
			.write(to: userKnownHostsURL)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o000],
			ofItemAtPath: userKnownHostsURL.path
		)
		defer {
			try? FileManager.default.setAttributes(
				[.posixPermissions: 0o600],
				ofItemAtPath: userKnownHostsURL.path
			)
		}
		let fileManager = TemporaryFileManager(directoryURL: directoryURL)
		let temporaryCopiesBefore = Self.temporaryTrustScopeCount(at: directoryURL)

		#expect(throws: (any Error).self) {
			try GitSSHTrustScope(userKnownHostsURL: userKnownHostsURL, fileManager: fileManager)
		}

		#expect(
			Self.temporaryTrustScopeCount(at: directoryURL) == temporaryCopiesBefore,
			"A failed trust scope must not leave a temporary known_hosts copy behind")
	}

	@Test
	func testUnusableKnownHostsPathFails() throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let userKnownHostsURL = directoryURL.appending(
			path: "known_hosts",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: userKnownHostsURL, withIntermediateDirectories: true)

		#expect(throws: (any Error).self) { try GitSSHTrustScope(userKnownHostsURL: userKnownHostsURL) }
	}

	private static func temporaryTrustScopeCount(at directoryURL: URL) -> Int {
		let contents =
			(try? FileManager.default.contentsOfDirectory(
				atPath: directoryURL.path
			)) ?? []
		return contents.filter { $0.hasPrefix("GrovesKnownHosts-") }.count
	}

	@Test
	func testTrustScopeKeepsHostKeyCheckingInteractive() throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let scope = try GitSSHTrustScope(
			userKnownHostsURL: directoryURL.appending(path: "known_hosts")
		)
		defer { scope.remove() }

		let options = scope.sshOptions.joined(separator: " ")

		#expect(options.contains("StrictHostKeyChecking=ask"))
		#expect(options.contains(scope.knownHostsURL.path))
		#expect(!(options.contains("StrictHostKeyChecking=no")))
	}
}
