import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryHistory",
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
		.featureRepositoryHistory,
		.featureRepositoryHistoryTests,
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryHistory",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryHistory]),
			testAction: .targets(
				[.testableTarget(target: .featureRepositoryHistoryTests)],
				configuration: .debug,
				options: .options(coverage: true)
			)
		)
	]
)
