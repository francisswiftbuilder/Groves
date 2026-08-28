import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryTree",
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
		.featureRepositoryTree,
		.featureRepositoryTreeTests,
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryTree",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryTree]),
			testAction: .targets(
				[.testableTarget(target: .featureRepositoryTreeTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
