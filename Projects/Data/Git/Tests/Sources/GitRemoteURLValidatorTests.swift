import Foundation
import Testing

@testable import DataGit

struct GitRemoteURLValidatorTests {
	@Test
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
			#expect(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds credentials in its userinfo")
		}
	}

	@Test
	func testWebSchemeWithoutUserInfoIsAccepted() {
		let remoteURLs = [
			"https://github.com/owner/repo.git",
			"http://127.0.0.1:8080/owner/repo.git",
			"https://github.com/owner/a@b.git",
		]

		for remoteURL in remoteURLs {
			#expect(
				!(GitRemoteURLValidator.containsEmbeddedCredential(remoteURL)),
				"\(remoteURL) carries no credentials")
		}
	}

	@Test
	func testCredentialQueryItemsAreRejected() {
		let remoteURLs = [
			"https://github.com/owner/repo.git?token=secret",
			"https://github.com/owner/repo.git?access_token=secret",
			"https://github.com/owner/repo.git?ref=main&private_token=secret",
			"https://github.com/owner/repo.git?PASSWORD=secret",
		]

		for remoteURL in remoteURLs {
			#expect(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds a credential query item")
		}
	}

	@Test
	func testPercentEncodedCredentialQueryItemsAreRejected() {
		let remoteURLs = [
			"https://github.com/owner/repo.git?to%6ben=secret",
			"https://github.com/owner/repo.git?%61ccess_token=secret",
			"https://github.com/owner/repo.git?private%5Ftoken=secret",
			"https://github.com/owner/repo.git?tok%ZZen=secret",
		]

		for remoteURL in remoteURLs {
			#expect(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds an encoded credential query item")
		}
	}

	@Test
	func testQueryItemsWithoutCredentialsAreAccepted() {
		let remoteURLs = [
			"https://github.com/owner/repo.git?ref=main",
			"https://github.com/owner/repo.git?token=",
		]

		for remoteURL in remoteURLs {
			#expect(
				!(GitRemoteURLValidator.containsEmbeddedCredential(remoteURL)),
				"\(remoteURL) carries no credential value")
		}
	}

	@Test
	func testSecureShellUserNameIsAccepted() {
		let remoteURLs = [
			"ssh://git@github.com/owner/repo.git",
			"git+ssh://git@github.com/owner/repo.git",
			"git://git@github.com/owner/repo.git",
			"git@github.com:owner/repo.git",
		]

		for remoteURL in remoteURLs {
			#expect(
				!(GitRemoteURLValidator.containsEmbeddedCredential(remoteURL)),
				"\(remoteURL) uses an SSH user name rather than a credential")
		}
	}

	@Test
	func testSecureShellPasswordIsRejected() {
		let remoteURLs = [
			"ssh://git:token@github.com/owner/repo.git",
			"git:token@github.com:owner/repo.git",
		]

		for remoteURL in remoteURLs {
			#expect(
				GitRemoteURLValidator.containsEmbeddedCredential(remoteURL),
				"\(remoteURL) embeds a password in its userinfo")
		}
	}

	@Test
	func testLocalPathsAreAccepted() {
		let remoteURLs = [
			"/Users/groves/repo",
			"/Users/groves@work/repo",
			"file:///Users/groves/repo",
			"../sibling/repo",
		]

		for remoteURL in remoteURLs {
			#expect(
				!(GitRemoteURLValidator.containsEmbeddedCredential(remoteURL)),
				"\(remoteURL) is a local path")
		}
	}

	@Test
	func testSurroundingWhitespaceIsIgnored() {
		#expect(
			GitRemoteURLValidator.containsEmbeddedCredential(
				"  https://user@github.com/owner/repo.git\n"
			))
		#expect(
			!(GitRemoteURLValidator.containsEmbeddedCredential(
				"  https://github.com/owner/repo.git\n"
			)))
	}

	@Test
	func testSSHRemoteDetection() {
		let sshRemoteURLs = [
			"ssh://git@github.com/owner/repo.git",
			"git+ssh://git@github.com/owner/repo.git",
			"git@github.com:owner/repo.git",
			"github.com:owner/repo.git",
		]
		let nonSSHRemoteURLs = [
			"https://github.com/owner/repo.git",
			"git://github.com/owner/repo.git",
			"file:///Users/groves/repo",
			"/Users/groves/repo",
			"../sibling/repo",
		]

		for remoteURL in sshRemoteURLs {
			#expect(GitRemoteURLValidator.isSSHRemote(remoteURL))
		}
		for remoteURL in nonSSHRemoteURLs {
			#expect(!(GitRemoteURLValidator.isSSHRemote(remoteURL)))
		}
	}
}
