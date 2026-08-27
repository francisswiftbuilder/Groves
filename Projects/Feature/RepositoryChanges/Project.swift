import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "FeatureRepositoryChanges",
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
		.featureRepositoryChanges
	],
	schemes: [
		.scheme(
			name: "FeatureRepositoryChanges",
			shared: true,
			buildAction: .buildAction(targets: [.featureRepositoryChanges])
		)
	]
)
