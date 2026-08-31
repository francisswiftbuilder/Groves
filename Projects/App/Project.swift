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
			entitlements: Permissions.appEntitlements,
			dependencies: [
				.core(implements: .gitCredential)
			],
			settings: askPassSettings
		),
		.target(
			name: TreesProduct.appTestsTargetName,
			destinations: environment.destinations,
			product: .unitTests,
			productName: TreesProduct.appTestsTargetName,
			bundleId: environment.organizationName + ".AppTests",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .default,
			sources: TreesProduct.appTestsSources,
			dependencies: .appTestsDependencies,
			settings: appTestsSettings
		),
	],
	schemes: [
		.appScheme,
		.scheme(
			name: TreesProduct.appTestsTargetName,
			shared: true,
			buildAction: .buildAction(targets: [.target(TreesProduct.appTestsTargetName)]),
			testAction: .targets(
				[.testableTarget(target: .target(TreesProduct.appTestsTargetName))],
				configuration: .debug,
				options: .options(coverage: true)
			)
		),
	]
)
