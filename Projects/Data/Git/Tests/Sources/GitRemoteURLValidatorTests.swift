import Foundation
import XCTest

@testable import DataGit

final class GitRemoteURLValidatorTests: XCTestCase {
	func testWebSchemeUserInfoIsRejected() {
		let remoteURLs = [
			"https://user@github.com/owner/repo.git",
			"https://user:token@github.com/owner/repo.git",
			"https://user:@github.com/owner/repo.git",
			"http://user@github.com/owner/repo.git",
			"HTTPS://user@github.com/owner/repo.git",
			"https://user%40evil.com@github.com/owner/repo.git",
			"https://user:token@ho st/owner/repo.git",
		]

		for remoteURL in remoteURLs {
			XCTAssertTrue(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds credentials in its userinfo"
			)
		}
	}

	func testWebSchemeWithoutUserInfoIsAccepted() {
		let remoteURLs = [
			"https://github.com/owner/repo.git",
			"http://127.0.0.1:8080/owner/repo.git",
			"https://github.com/owner/a@b.git",
		]

		for remoteURL in remoteURLs {
			XCTAssertFalse(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) carries no credentials"
			)
		}
	}

	func testCredentialQueryItemsAreRejected() {
		let remoteURLs = [
			"https://github.com/owner/repo.git?token=secret",
			"https://github.com/owner/repo.git?access_token=secret",
			"https://github.com/owner/repo.git?ref=main&private_token=secret",
			"https://github.com/owner/repo.git?PASSWORD=secret",
		]

		for remoteURL in remoteURLs {
			XCTAssertTrue(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds a credential query item"
			)
		}
	}

	func testQueryItemsWithoutCredentialsAreAccepted() {
		let remoteURLs = [
			"https://github.com/owner/repo.git?ref=main",
			"https://github.com/owner/repo.git?token=",
		]

		for remoteURL in remoteURLs {
			XCTAssertFalse(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) carries no credential value"
			)
		}
	}

	func testSecureShellUserNameIsAccepted() {
		let remoteURLs = [
			"ssh://git@github.com/owner/repo.git",
			"git+ssh://git@github.com/owner/repo.git",
			"git://git@github.com/owner/repo.git",
			"git@github.com:owner/repo.git",
		]

		for remoteURL in remoteURLs {
			XCTAssertFalse(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) uses an SSH user name rather than a credential"
			)
		}
	}

	func testSecureShellPasswordIsRejected() {
		let remoteURLs = [
			"ssh://git:token@github.com/owner/repo.git",
			"git:token@github.com:owner/repo.git",
		]

		for remoteURL in remoteURLs {
			XCTAssertTrue(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds a password in its userinfo"
			)
		}
	}

	func testLocalPathsAreAccepted() {
		let remoteURLs = [
			"/Users/trees/repo",
			"/Users/trees@work/repo",
			"file:///Users/trees/repo",
			"../sibling/repo",
		]

		for remoteURL in remoteURLs {
			XCTAssertFalse(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) is a local path"
			)
		}
	}

	func testSurroundingWhitespaceIsIgnored() {
		XCTAssertTrue(
			GitRemoteURLValidator.containsEmbeddedCredential(
				"  https://user@github.com/owner/repo.git\n"
			)
		)
		XCTAssertFalse(
			GitRemoteURLValidator.containsEmbeddedCredential(
				"  https://github.com/owner/repo.git\n"
			)
		)
	}
}
