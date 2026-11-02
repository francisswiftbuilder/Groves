import Foundation

public final class GitHubAccountSelection: @unchecked Sendable {
	private let defaults: UserDefaults
	private let key = "activeGitHubAccount"

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	public var account: String? {
		defaults.string(forKey: key)
	}

	public func select(_ account: String?) {
		if let account {
			defaults.set(account, forKey: key)
		} else {
			defaults.removeObject(forKey: key)
		}
	}
}
