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
			name: GrovesProduct.askPassTargetName,
			destinations: environment.destinations,
			product: .commandLineTool,
			productName: GrovesProduct.askPassTargetName,
			bundleId: environment.organizationName + ".AskPass",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .default,
			sources: GrovesProduct.askPassSources,
			entitlements: Permissions.appEntitlements,
			dependencies: [
				.core(implements: .gitCredential)
			],
			settings: askPassSettings
		),
		.target(
			name: GrovesProduct.appTestsTargetName,
			destinations: environment.destinations,
			product: .unitTests,
			productName: GrovesProduct.appTestsTargetName,
			bundleId: environment.organizationName + ".AppTests",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .default,
			sources: GrovesProduct.appTestsSources,
			dependencies: .appTestsDependencies,
			settings: appTestsSettings
		),
	],
	schemes: [
		.appScheme,
		.scheme(
			name: GrovesProduct.appTestsTargetName,
			shared: true,
			buildAction: .buildAction(targets: [.target(GrovesProduct.appTestsTargetName)]),
			testAction: .targets(
				[.testableTarget(target: .target(GrovesProduct.appTestsTargetName))],
				configuration: .debug,
				options: .options(coverage: true)
			)
		),
	]
)
