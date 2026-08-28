import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
	name: environment.name,
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
		.app,
		.target(
			name: TreesProduct.askPassTargetName,
			destinations: environment.destinations,
			product: .commandLineTool,
			productName: TreesProduct.askPassTargetName,
			bundleId: environment.organizationName + ".AskPass",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .default,
			sources: TreesProduct.askPassSources,
			dependencies: [
				.core(implements: .gitCredential)
			],
			settings: askPassSettings
		),
	],
	schemes: [
		.appScheme
	]
)
