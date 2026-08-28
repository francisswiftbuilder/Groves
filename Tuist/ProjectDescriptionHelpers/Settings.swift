import ConfigurationPlugin
import ProjectDescription

private var developmentSigningSettings: SettingsDictionary {
	let codeSignIdentity = Environment.codeSignIdentity.getString(default: "")
	let developmentTeam = Environment.developmentTeam.getString(default: "")

	guard codeSignIdentity.isEmpty == false, developmentTeam.isEmpty == false else {
		return [:]
	}

	return [
		"CODE_SIGN_IDENTITY": .string(codeSignIdentity),
		"CODE_SIGN_STYLE": "Manual",
		"DEVELOPMENT_TEAM": .string(developmentTeam),
	]
}

private var appTargetSettings: SettingsDictionary {
	var settings: SettingsDictionary = [
		"PRODUCT_NAME": "Trees"
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

public var askPassSettings: Settings {
	.settings(base: baseSettings.merging(developmentSigningSettings) { _, signing in signing })
}

extension Settings: TargetSettings {
	public static var appSettings: Settings? {
		.settings(base: appTargetSettings)
	}
}
