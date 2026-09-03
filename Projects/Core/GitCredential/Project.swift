import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "CoreGitCredential",
	options: .options(
		automaticSchemesOptions: .disabled,
		textSettings: .textSettings(
			usesTabs: true,
			indentWidth: 2,
			tabWidth: 2
		)
	),
	settings: .settings(
		base: baseSettings,
		configurations: ConfigurationType.configurations()
	),
	targets: [
		.coreGitCredential,
		.coreGitCredentialTests,
	],
	schemes: [
		.scheme(
			name: "CoreGitCredential",
			shared: true,
			buildAction: .buildAction(targets: [.coreGitCredential]),
			testAction: .targets(
				[.testableTarget(target: .coreGitCredentialTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
