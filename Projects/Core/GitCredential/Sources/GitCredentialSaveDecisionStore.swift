import Foundation

public final class GitCredentialSaveDecisionStore: @unchecked Sendable {
	private let defaults: UserDefaults

	public init(suiteName: String = "io.github.francisswiftbuilder.Trees.GitCredential") {
		defaults = UserDefaults(suiteName: suiteName) ?? .standard
	}

	public func setShouldSave(_ shouldSave: Bool, operationID: String) {
		defaults.set(shouldSave, forKey: key(operationID))
	}

	public func consumeShouldSave(operationID: String) -> Bool {
		let key = key(operationID)
		defer { defaults.removeObject(forKey: key) }
		guard defaults.object(forKey: key) != nil else { return true }
		return defaults.bool(forKey: key)
	}

	public func discard(operationID: String) {
		defaults.removeObject(forKey: key(operationID))
	}

	private func key(_ operationID: String) -> String {
		"save.\(operationID)"
	}
}
