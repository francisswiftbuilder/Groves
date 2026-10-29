import Foundation
import Testing

@testable import CoreGitCredential

struct GitHubAuthenticationTests {
	@Test
	func emptyPublicEmailUsesNoreplyAddress() throws {
		let data = Data(#"{"login":"octocat","id":42,"name":"","email":"  "}"#.utf8)
		let account = try JSONDecoder().decode(GitHubAccount.self, from: data)

		#expect(account.commitEmail == "42+octocat@users.noreply.github.com")
	}

	@Test
	func identityNormalizesOuterSpacesWithoutAcceptingMalformedEmail() {
		#expect(GitIdentityConfiguration(name: " User ", email: " user@example.com ").isValid)
		for email in ["user@", "@example.com", "user@@example.com", "user name@example.com"] {
			#expect(!GitIdentityConfiguration(name: "User", email: email).isValid)
		}
	}

	@Test
	func verifiedAccountUsesNoreplyEmailWhenEmailIsPrivate() async throws {
		let account = try await client().account(token: "valid-test-token")
		#expect(account.login == "octocat")
		#expect(account.commitEmail == "42+octocat@users.noreply.github.com")
	}

	@Test
	func rejectedTokenProducesActionableError() async throws {
		await #expect(throws: GitHubAuthenticationError.self) {
			_ = try await client().account(token: "expired-test-token")
		}
	}

	@Test
	func forbiddenTokenDoesNotReturnAnAccount() async throws {
		do {
			_ = try await client().account(token: "forbidden-test-token")
			Issue.record("Expected a permission error")
		} catch GitHubAuthenticationError.forbidden {}
	}

	@Test
	func rejectsWhitespaceInToken() async throws {
		for token in ["token\nheader", "token\u{0}header", "token\u{7f}header"] {
			await #expect(throws: GitHubAuthenticationError.self) {
				_ = try await client().account(token: token)
			}
		}
	}

	@Test
	func identityRejectsConfigurationInjection() {
		#expect(!GitIdentityConfiguration(name: "User\n[credential]", email: "a@b.com").isValid)
		#expect(!GitIdentityConfiguration(name: "", email: "a@b.com").isValid)
		#expect(!GitIdentityConfiguration(name: "User", email: "invalid").isValid)
	}

	private func client() -> GitHubAuthenticationClient {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [GitHubAuthenticationURLProtocol.self]
		return GitHubAuthenticationClient(session: URLSession(configuration: configuration))
	}
}
