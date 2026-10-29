import Testing

@testable import DataGit

struct GitRemoteParsingTests {
	@Test
	func readsConfiguredURLsWithoutInventingAnInheritedPushURL() throws {
		let output =
			"remote.origin.url\nhttps://example.com/repo.git\0remote.origin.fetch\n+refs/heads/*:refs/remotes/origin/*\0"
		let remote = try #require(GitOutputParser.parseRemotes(output).first)
		#expect(remote.fetchURL == "https://example.com/repo.git")
		#expect(remote.pushURL == nil)
		#expect(remote.pushURLs.isEmpty)
	}

	@Test
	func preservesMultipleURLsAndRemoteNamesContainingDotsOrSlashes() throws {
		let output =
			"remote.team/origin.example.url\nfirst\0remote.team/origin.example.url\nsecond\0remote.team/origin.example.pushurl\npush-one\0remote.team/origin.example.pushurl\npush-two\0remote.pushdefault\norigin\0"
		let remotes = GitOutputParser.parseRemotes(output)
		let remote = try #require(remotes.first)
		#expect(remotes.count == 1)
		#expect(remote.name == "team/origin.example")
		#expect(remote.fetchURLs == ["first", "second"])
		#expect(remote.pushURLs == ["push-one", "push-two"])
		#expect(remote.hasMultipleURLs)
	}

	@Test
	func parsesFullyQualifiedTrackingRefsAndSkipsSymbolicHEAD() {
		let output = """
			refs/remotes/origin/main\t1234567\t1234567890abcdef\t
			refs/remotes/origin/feature/sidebar\t2345678\t234567890abcdef1\t
			refs/remotes/origin/HEAD\t1234567\t1234567890abcdef\trefs/remotes/origin/main
			"""
		let branches = GitOutputParser.parseRemoteBranches(output, remoteNames: ["origin"])
		#expect(branches.map(\.name) == ["main", "feature/sidebar"])
		#expect(branches.map(\.remoteName) == ["origin", "origin"])
		#expect(branches.first?.fullName == "origin/main")
	}

	@Test
	func matchesTheCompleteRemoteNameBeforeSplittingTheBranch() throws {
		let output = "refs/remotes/team/origin/feature/main\tabcdef0\tabcdef0123456789\t"
		let branch = try #require(
			GitOutputParser.parseRemoteBranches(output, remoteNames: ["team", "team/origin"]).first)
		#expect(branch.remoteName == "team/origin")
		#expect(branch.name == "feature/main")
		#expect(branch.fullName == "team/origin/feature/main")
	}
}
