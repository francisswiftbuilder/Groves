import ConfigurationPlugin
import ProjectDescription

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

extension Settings: TargetSettings {
	public static var appSettings: Settings? {
		.settings(
			base: [
				"PRODUCT_NAME": "Trees"
			]
		)
	}
}
