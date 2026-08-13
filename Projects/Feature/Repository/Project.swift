import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepository",
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
		.featureRepository,
		.featureRepositoryInterface,
		.featureRepositoryTests,
	],
	schemes: [
		.scheme(
			name: "FeatureRepository",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepository]),
			testAction: .targets(
				[.testableTarget(target: .featureRepositoryTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
