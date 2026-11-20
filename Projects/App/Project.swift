import ConfigurationPlugin
import ProjectDescription
import ProjectDescriptionHelpers

let appTarget: Target = {
	var target: Target = .app
	target.name = environment.name
	return target
}()
let appReference = TargetReference.target(appTarget.name)

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
		appTarget,
		.target(
			name: PluminonProduct.askPassTargetName,
			destinations: environment.destinations,
			product: .app,
			productName: PluminonProduct.askPassTargetName,
			bundleId: environment.organizationName + ".AskPass",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .extendingDefault(with: [
				"LSUIElement": .boolean(true),
				"PluminonDataNamespace": "$(PLUMINON_DATA_NAMESPACE)",
				"PluminonCredentialNamespace": "$(PLUMINON_BUNDLE_IDENTIFIER)",
			]),
			sources: PluminonProduct.askPassSources,
			entitlements: Permissions.appEntitlements,
			dependencies: [
				.core(implements: .gitCredential)
			],
			settings: askPassSettings
		),
		.target(
			name: PluminonProduct.appTestsTargetName,
			destinations: environment.destinations,
			product: .unitTests,
			productName: PluminonProduct.appTestsTargetName,
			bundleId: environment.organizationName + ".AppTests",
			deploymentTargets: environment.deploymentTargets,
			infoPlist: .default,
			sources: PluminonProduct.appTestsSources,
			dependencies: .appTestsDependencies,
			settings: appTestsSettings
		),
	],
	schemes: [
		.scheme(
			name: environment.name,
			shared: true,
			buildAction: .buildAction(targets: [appReference]),
			runAction: .runAction(configuration: .debug, executable: appReference),
			archiveAction: .appArchiveAction
		),
		.scheme(
			name: PluminonProduct.appTestsTargetName,
			shared: true,
			buildAction: .buildAction(targets: [.target(PluminonProduct.appTestsTargetName)]),
			testAction: .targets(
				[.testableTarget(target: .target(PluminonProduct.appTestsTargetName))],
				configuration: .debug,
				options: .options(coverage: true)
			)
		),
	]
)
