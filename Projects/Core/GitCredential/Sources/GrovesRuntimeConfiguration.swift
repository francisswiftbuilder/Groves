import Foundation

public enum GrovesRuntimeConfiguration {
	public static var displayName: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Groves"
	}

	public static var dataNamespace: String {
		Bundle.main.object(forInfoDictionaryKey: "GrovesDataNamespace") as? String ?? "Groves"
	}

	public static var credentialNamespace: String {
		Bundle.main.object(forInfoDictionaryKey: "GrovesCredentialNamespace") as? String
			?? "io.github.francisswiftbuilder.Groves"
	}

	public static var applicationSupportURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appending(path: dataNamespace, directoryHint: .isDirectory)
	}
}
