import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "CoreRepositoryDiff",
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
		.coreRepositoryDiff,
		.coreRepositoryDiffTests,
	],
	schemes: [
		.scheme(
			name: "CoreRepositoryDiff",
			shared: true,
			buildAction: .buildAction(targets: [.coreRepositoryDiff]),
			testAction: .targets(
				[.testableTarget(target: .coreRepositoryDiffTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
