import Foundation

public enum PluminonRuntimeConfiguration {
	public static var displayName: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pluminon"
	}

	public static var dataNamespace: String {
		Bundle.main.object(forInfoDictionaryKey: "PluminonDataNamespace") as? String ?? "Pluminon"
	}

	public static var credentialNamespace: String {
		Bundle.main.object(forInfoDictionaryKey: "PluminonCredentialNamespace") as? String
			?? "com.francisswiftbuilder.pluminon"
	}

	public static var applicationSupportURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appending(path: dataNamespace, directoryHint: .isDirectory)
	}
}
