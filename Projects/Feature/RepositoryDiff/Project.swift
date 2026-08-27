import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryDiff",
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
		.featureRepositoryDiff
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryDiff",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryDiff])
		)
	]
)
