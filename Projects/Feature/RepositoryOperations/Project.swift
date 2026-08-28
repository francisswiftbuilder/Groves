import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryOperations",
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
		.featureRepositoryOperations,
		.featureRepositoryOperationsTests,
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryOperations",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryOperations]),
			testAction: .targets(
				[.testableTarget(target: .featureRepositoryOperationsTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
