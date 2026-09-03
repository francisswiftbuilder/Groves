import ConfigurationPlugin
import ProjectDescription

private var developmentSigningSettings: SettingsDictionary {
	let codeSignIdentity = Environment.codeSignIdentity.getString(default: "")
	let developmentTeam = Environment.developmentTeam.getString(default: "")

	guard codeSignIdentity.isEmpty == developmentTeam.isEmpty else {
		fatalError(
			"TUIST_CODE_SIGN_IDENTITY and TUIST_DEVELOPMENT_TEAM must both be set or both be empty."
		)
	}
	guard codeSignIdentity.isEmpty == false else { return [:] }

	return [
		"CODE_SIGN_IDENTITY": "Apple Development",
		"CODE_SIGN_STYLE": "Automatic",
		"DEVELOPMENT_TEAM": .string(developmentTeam),
	]
}

private var appTargetSettings: SettingsDictionary {
	var settings: SettingsDictionary = [
		"ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
		"CODE_SIGN_ENTITLEMENTS": .string(Permissions.appEntitlementsBuildSetting),
		"PRODUCT_NAME": "Groves",
	]
	settings.merge(developmentSigningSettings) { _, signing in signing }
	return settings
}

public let baseSettings: SettingsDictionary = [
	"CODE_SIGN_STYLE": "Automatic",
	"CLANG_ENABLE_MODULES": "YES",
	"CLANG_ENABLE_MODULE_VERIFIER": "YES",
	"CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES": "YES",
	"ENABLE_USER_SCRIPT_SANDBOXING": "YES",
	"ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
	"SWIFT_VERSION": "6.0",
	"SWIFT_STRICT_CONCURRENCY": "complete",
]

// The app target renames its product, so the generated TEST_HOST keeps the target name for the
// executable and no longer matches the bundle. Point it at the renamed product instead.
public var appTestsSettings: Settings {
	let executablePath =
		"$(BUILT_PRODUCTS_DIR)/\(environment.name).app"
		+ "/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/\(environment.name)"
	let testHostSettings: SettingsDictionary = [
		"TEST_HOST": .string(executablePath),
		"BUNDLE_LOADER": "$(TEST_HOST)",
	]
	return .settings(base: baseSettings.merging(testHostSettings) { _, host in host })
}

public var askPassSettings: Settings {
	.settings(base: baseSettings.merging(developmentSigningSettings) { _, signing in signing })
}

extension Settings: TargetSettings {
	// The unit tests run against the app bundle, and a static archive only hands the linker the
	// object files the app itself names. Load every object in debug so the tests can reach the
	// types the app never mentions; the shipping configurations stay lean.
	public static var appSettings: Settings? {
		.settings(
			base: appTargetSettings,
			configurations: ConfigurationType.configurations().map { configuration in
				configuration.name == "Debug"
					? .debug(
						name: configuration.name,
						settings: ["OTHER_LDFLAGS": .array(["$(inherited)", "-all_load"])],
						xcconfig: ConfigurationType.debug.xcconfig
					)
					: configuration
			}
		)
	}
}
