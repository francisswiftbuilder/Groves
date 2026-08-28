import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryStashes",
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
		.featureRepositoryStashes,
		.featureRepositoryStashesTests,
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryStashes",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryStashes]),
			testAction: .targets(
				[.testableTarget(target: .featureRepositoryStashesTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
