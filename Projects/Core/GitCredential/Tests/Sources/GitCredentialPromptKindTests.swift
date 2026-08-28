import Foundation
import Testing

@testable import CoreGitCredential

struct GitCredentialPromptKindTests {
	@Test
	func hostTrustPromptsAreClassifiedByTheirAuthenticityWording() {
		#expect(
			GitCredentialPromptKind(prompt: "The authenticity of host 'github.com' can't be established.")
				== .hostTrust
		)
		#expect(GitCredentialPromptKind(prompt: "RSA key fingerprint is SHA256:abc.") == .hostTrust)
	}

	@Test
	func usernamePromptsAreClassifiedSeparatelyFromSecrets() {
		#expect(GitCredentialPromptKind(prompt: "Username for 'https://github.com':") == .username)
		#expect(GitCredentialPromptKind(prompt: "Enter user name:") == .username)
	}

	@Test
	func anyOtherPromptIsTreatedAsASecret() {
		#expect(GitCredentialPromptKind(prompt: "Password for 'https://github.com':") == .secret)
		#expect(
			GitCredentialPromptKind(prompt: "Enter passphrase for key '/tmp/id_ed25519':") == .secret)
	}

	@Test
	func onlyAQuotedPassphrasePromptResolvesAnSSHKeyDescriptor() {
		let descriptor = GitCredentialDescriptor.sshKey(
			forPassphrasePrompt: "Enter passphrase for key '/tmp/id_ed25519':"
		)

		#expect(descriptor == .sshKey(at: "/tmp/id_ed25519"))
		#expect(GitCredentialDescriptor.sshKey(forPassphrasePrompt: "Password:") == nil)
		#expect(
			GitCredentialDescriptor.sshKey(forPassphrasePrompt: "Enter passphrase for key '':") == nil
		)
		#expect(
			GitCredentialDescriptor.sshKey(forPassphrasePrompt: "Enter passphrase for key:") == nil
		)
	}
}
