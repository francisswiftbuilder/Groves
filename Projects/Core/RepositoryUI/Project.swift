import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: "CoreRepositoryUI",
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
		.coreRepositoryUI
	],
	schemes: [
		.scheme(
			name: "CoreRepositoryUI",
			shared: true,
			buildAction: .buildAction(targets: [.coreRepositoryUI])
		)
	]
)
