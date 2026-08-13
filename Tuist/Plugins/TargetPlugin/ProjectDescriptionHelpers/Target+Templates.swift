import Foundation
import ProjectDescription

public struct TargetFactory {
	var name: String
	var destinations: Destinations
	var product: Product
	var productName: String?
	var bundlePrefix: String
	var deploymentTargets: DeploymentTargets
	var infoPlist: InfoPlist?
	var sources: SourceFilesList?
	var resources: ResourceFileElements?
	var copyFiles: [CopyFilesAction]?
	var headers: Headers?
	var entitlements: Path?
	var scripts: [TargetScript]
	var dependencies: [TargetDependency]
	var settings: Settings?
	var coreDataModels: [CoreDataModel]

	public init(
		name: String = "",
		destinations: Destinations,
		product: Product = .staticLibrary,
		productName: String? = nil,
		bundlePrefix: String,
		deploymentTargets: DeploymentTargets,
		infoPlist: InfoPlist? = .default,
		sources: SourceFilesList? = nil,
		resources: ResourceFileElements? = nil,
		copyFiles: [CopyFilesAction]? = nil,
		headers: Headers? = nil,
		entitlements: Path? = nil,
		scripts: [TargetScript] = [],
		dependencies: [TargetDependency] = [],
		settings: Settings? = nil,
		coreDataModels: [CoreDataModel] = []
	) {
		self.name = name
		self.destinations = destinations
		self.product = product
		self.productName = productName
		self.bundlePrefix = bundlePrefix
		self.deploymentTargets = deploymentTargets
		self.infoPlist = infoPlist
		self.sources = sources
		self.resources = resources
		self.copyFiles = copyFiles
		self.headers = headers
		self.entitlements = entitlements
		self.scripts = scripts
		self.dependencies = dependencies
		self.settings = settings
		self.coreDataModels = coreDataModels
	}
}

extension Target {
	private static func make(factory: TargetFactory) -> Self {
		var bundleId = factory.bundlePrefix
		let shouldAppendName: Bool = {
			guard !factory.name.isEmpty else { return false }
			if factory.product == .app {
				return factory.name != ModulePath.app.name
			}
			return true
		}()
		if shouldAppendName {
			bundleId.append(".\(factory.name)")
		}
		return target(
			name: factory.name,
			destinations: factory.destinations,
			product: factory.product,
			productName: factory.productName,
			bundleId: bundleId,
			deploymentTargets: factory.deploymentTargets,
			infoPlist: factory.infoPlist,
			sources: factory.sources,
			resources: factory.resources,
			copyFiles: factory.copyFiles,
			headers: factory.headers,
			entitlements: factory.entitlements.map { .file(path: $0) },
			scripts: factory.scripts,
			dependencies: factory.dependencies,
			settings: factory.settings,
			coreDataModels: factory.coreDataModels
		)
	}
}

extension Target {
	public static func app(implements module: ModuleAppType? = nil, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.app.name
		newFactory.sources = .paths([.relativeToRoot(ModulePath.app.path + "/Sources/**")])
		newFactory.resources = .resources(
			[.glob(pattern: .relativeToRoot(ModulePath.app.path + "/Resources/**"))]
		)
		let path = Path.relativeToRoot(
			ModulePath.feature(module).path + "/SupportFiles/App.entitlements"
		)
		if FileManager.default.fileExists(atPath: path.pathString) {
			newFactory.entitlements = path
		}
		newFactory.product = .app
		return make(factory: newFactory)
	}

	public static func app(tests module: ModuleAppType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.app.tests
		newFactory.sources = .paths([.relativeToRoot(ModulePath.app.path + "/Tests/Sources**")])
		newFactory.product = .unitTests
		return make(factory: newFactory)
	}

	public static func app(testing module: ModuleAppType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.app.testing
		newFactory.sources = .paths([.relativeToRoot(ModulePath.app.path + "/Testing/Sources**")])
		return make(factory: newFactory)
	}
}

extension Target {
	public static func widget(
		implements module: ModuleAppExtensionType? = nil, factory: TargetFactory
	) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.appExtension(module).name
		newFactory.product = .appExtension

		if let name = module?.name {
			newFactory.sources = .paths([
				.relativeToRoot(ModulePath.appExtension(module).path + "/Widget/\(name)/Sources/**")
			])
			newFactory.resources = .resources([
				.glob(
					pattern: .relativeToRoot(
						ModulePath.appExtension(module).path + "/Widget/\(name)/Resources/**")
				)
			])
			newFactory.entitlements = .relativeToRoot(
				ModulePath.appExtension(module).path + "/Widget/\(name)/SupportFiles/\(name).entitlements"
			)
		}
		newFactory.infoPlist?.add(
			"$(PRODUCT_NAME)",
			forKey: "CFBundleDisplayName"
		)
		newFactory.infoPlist?.add(
			[
				"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
			],
			forKey: "NSExtension"
		)
		return make(factory: newFactory)
	}

	public static func intents(
		implements module: ModuleAppExtensionType? = nil, factory: TargetFactory
	) -> Self {
		var newFactory = factory
		newFactory.product = .extensionKitExtension
		newFactory.name = ModulePath.appExtension(module).name

		if let name = module?.name {
			newFactory.sources = .paths([
				.relativeToRoot(ModulePath.appExtension(module).path + "/Intents/\(name)/Sources/**")
			])
			newFactory.resources = .resources([
				.glob(
					pattern: .relativeToRoot(
						ModulePath.appExtension(module).path + "/Intents/\(name)/Resources/**")
				)
			])
			newFactory.entitlements = .relativeToRoot(
				ModulePath.appExtension(module).path
					+ "/Intents/\(module?.name ?? "")/SupportFiles/\(name).entitlements"
			)
		}

		newFactory.infoPlist?.add(
			[
				"EXExtensionPointIdentifier": "com.apple.appintents-extension"
			],
			forKey: "EXAppExtensionAttributes"
		)
		return make(factory: newFactory)
	}

	public static func notificationService(
		implements module: ModuleAppExtensionType? = nil, factory: TargetFactory
	) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.appExtension(module).name
		newFactory.product = .appExtension
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.appExtension(module).path + "/NotificationService/Sources/**")
		])
		newFactory.resources = .resources([
			.glob(
				pattern: .relativeToRoot(
					ModulePath.appExtension(module).path + "/NotificationService/Resources/**")
			)
		])
		newFactory.infoPlist?.add(
			"$(PRODUCT_NAME)",
			forKey: "CFBundleDisplayName"
		)
		newFactory.infoPlist?.add(
			[
				"NSExtensionPointIdentifier": "com.apple.usernotifications.service",
				"NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService",
			],
			forKey: "NSExtension"
		)
		return make(factory: newFactory)
	}
}

extension Target {
	public static func feature(implements module: ModuleFeatureType? = nil, factory: TargetFactory)
		-> Self
	{
		var newFactory = factory
		newFactory.name = ModulePath.feature(module).name
		newFactory.sources = .paths([.relativeToRoot(ModulePath.feature(module).path + "/Sources/**")])
		return make(factory: newFactory)
	}

	public static func feature(tests module: ModuleFeatureType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.feature(module).tests
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.feature(module).path + "/Tests/Sources/**")
		])
		newFactory.product = .unitTests
		return make(factory: newFactory)
	}

	public static func feature(testing module: ModuleFeatureType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.feature(module).testing
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.feature(module).path + "/Testing/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func feature(interface module: ModuleFeatureType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.feature(module).interface
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.feature(module).path + "/Interface/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func feature(example module: ModuleFeatureType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.feature(module).example
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.feature(module).path + "/Example/Sources/**")
		])
		newFactory.resources = .resources(
			[.glob(pattern: .relativeToRoot(ModulePath.feature(module).path + "/Example/Resources/**"))]
		)
		newFactory.infoPlist?.add(
			"LaunchScreen.storyboard",
			forKey: "UILaunchStoryboardName"
		)
		let path = Path.relativeToRoot(
			ModulePath.feature(module).path + "/Example/SupportFiles/Example\(module.name).entitlements"
		)
		if FileManager.default.fileExists(atPath: path.pathString) {
			newFactory.entitlements = path
		}

		newFactory.product = .app
		return make(factory: newFactory)
	}
}

extension Target {
	public static func domain(implements module: ModuleDomainType? = nil, factory: TargetFactory)
		-> Self
	{
		var newFactory = factory
		newFactory.name = ModulePath.domain(module).name
		newFactory.sources = .paths([.relativeToRoot(ModulePath.domain(module).path + "/Sources/**")])
		return make(factory: newFactory)
	}

	public static func domain(tests module: ModuleDomainType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.domain(module).tests
		newFactory.product = .unitTests
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.domain(module).path + "/Tests/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func domain(testing module: ModuleDomainType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.domain(module).testing
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.domain(module).path + "/Testing/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func domain(interface module: ModuleDomainType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.domain(module).interface
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.domain(module).path + "/Interface/Sources/**")
		])
		return make(factory: newFactory)
	}
}

extension Target {
	public static func data(implements module: ModuleDataType? = nil, factory: TargetFactory) -> Self
	{
		var newFactory = factory
		newFactory.name = ModulePath.data(module).name
		newFactory.sources = .paths([.relativeToRoot(ModulePath.data(module).path + "/Sources/**")])
		return make(factory: newFactory)
	}

	public static func data(tests module: ModuleDataType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.data(module).tests
		newFactory.product = .unitTests
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.data(module).path + "/Tests/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func data(testing module: ModuleDataType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.data(module).testing
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.data(module).path + "/Testing/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func data(interface module: ModuleDataType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.data(module).interface
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.data(module).path + "/Interface/Sources/**")
		])
		return make(factory: newFactory)
	}
}

extension Target {
	public static func core(implements module: ModuleCoreType? = nil, factory: TargetFactory) -> Self
	{
		var newFactory = factory
		newFactory.name = ModulePath.core(module).name
		newFactory.sources = .paths([.relativeToRoot(ModulePath.core(module).path + "/Sources/**")])
		return make(factory: newFactory)
	}

	public static func core(tests module: ModuleCoreType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.core(module).tests
		newFactory.product = .unitTests
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.core(module).path + "/Tests/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func core(testing module: ModuleCoreType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.core(module).testing
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.core(module).path + "/Testing/Sources/**")
		])
		return make(factory: newFactory)
	}

	public static func core(interface module: ModuleCoreType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.core(module).interface
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.core(module).path + "/Interface/Sources/**")
		])
		return make(factory: newFactory)
	}
}

extension Target {
	public static func shared(implements module: ModuleSharedType? = nil, factory: TargetFactory)
		-> Self
	{
		var newFactory = factory
		newFactory.name = ModulePath.shared(module).name
		newFactory.sources = .paths(
			[.relativeToRoot(ModulePath.shared(module).path + "/Sources/**")]
		)
		newFactory.resources = .resources(
			[.glob(pattern: .relativeToRoot(ModulePath.shared(module).path + "/Resources/**"))]
		)
		return make(factory: newFactory)
	}

	public static func shared(interface module: ModuleSharedType, factory: TargetFactory) -> Self {
		var newFactory = factory
		newFactory.name = ModulePath.shared(module).interface
		newFactory.sources = .paths([
			.relativeToRoot(ModulePath.shared(module).path + "/Interface/Sources/**")
		])
		return make(factory: newFactory)
	}
}
