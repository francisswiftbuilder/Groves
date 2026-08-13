import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "DataGit",
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
		.dataGit,
		.dataGitTests,
	],
	schemes: [
		.scheme(
			name: "DataGit",
			shared: true,
			buildAction: .buildAction(targets: [.dataGit]),
			testAction: .targets(
				[.testableTarget(target: .dataGitTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
