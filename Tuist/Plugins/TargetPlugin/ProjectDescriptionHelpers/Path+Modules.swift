import Foundation
import ProjectDescription

public protocol ModuleType {
	var name: String { get }
}

public protocol ModuleAppType: ModuleType {}

public protocol ModuleAppExtensionType: ModuleType {}

public protocol ModuleFeatureType: ModuleType {}

public protocol ModuleDomainType: ModuleType {}

public protocol ModuleDataType: ModuleType {}

public protocol ModuleCoreType: ModuleType {}

public protocol ModuleSharedType: ModuleType {}

public enum ModulePath {
	case app
	case appExtension(ModuleType?)
	case feature(ModuleType?)
	case domain(ModuleType?)
	case data(ModuleType?)
	case core(ModuleType?)
	case shared(ModuleType?)

	private var prefix: String {
		switch self {
		case .app: return "App"
		case .appExtension: return "AppExtension"
		case .feature: return "Feature"
		case .domain: return "Domain"
		case .data: return "Data"
		case .core: return "Core"
		case .shared: return "Shared"
		}
	}

	private var module: ModuleType? {
		switch self {
		case .app: return nil
		case .appExtension(let module): return module
		case .feature(let module): return module
		case .domain(let module): return module
		case .data(let module): return module
		case .core(let module): return module
		case .shared(let module): return module
		}
	}

	var path: String {
		switch self {
		case .app, .appExtension:
			return "Projects/\(prefix)"

		case .feature(let module), .domain(let module), .data(let module), .core(let module),
			.shared(let module):
			guard let moduleName = module?.name else {
				return "Projects/\(prefix)"
			}
			return "Projects/\(prefix)/\(moduleName)"
		}
	}

	public var name: String {
		guard let moduleName = module?.name else { return prefix }
		return "\(prefix)\(moduleName)"
	}

	public var interface: String {
		guard let moduleName = module?.name else { return prefix }
		return "\(prefix)\(moduleName)" + "Interface"
	}

	public var testing: String {
		guard let moduleName = module?.name else { return prefix }
		return "\(prefix)\(moduleName)" + "Testing"
	}

	public var tests: String {
		guard let moduleName = module?.name else { return prefix }
		return "\(prefix)\(moduleName)" + "Tests"
	}

	public var example: String {
		guard let moduleName = module?.name else { return prefix }
		return "\(prefix)\(moduleName)" + "Example"
	}
}

// MARK: ProjectDescription.Path + App

extension ProjectDescription.Path {
	public static var app: Self {
		return .relativeToRoot(ModulePath.app.path)
	}
}

// MARK: ProjectDescription.Path + Extension

extension ProjectDescription.Path {
	public static var widget: Self {
		return .relativeToRoot("Projects/AppExtension/Widget")
	}

	public static func widget(implementation module: ModuleType) -> Self {
		return .relativeToRoot("Projects/AppExtension/Widget/\(ModulePath.appExtension(module).path)")
	}

	public static func intents(implementation module: ModuleType) -> Self {
		return .relativeToRoot("Projects/AppExtension/Intents/\(ModulePath.appExtension(module).path)")
	}

	public static func notificationService(implementation module: ModuleType) -> Self {
		return .relativeToRoot("Projects/AppExtension/NotificationService")
	}
}

// MARK: ProjectDescription.Path + Feature

extension ProjectDescription.Path {
	public static var feature: Self {
		return .relativeToRoot(ModulePath.feature(nil).path)
	}

	public static func feature(implementation module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.feature(module).path)
	}

	public static func feature(interface module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.feature(module).path + "/Interface")
	}

	public static func feature(tests module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.feature(module).path + "/Tests")
	}

	public static func feature(testing module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.feature(module).path + "/Testing")
	}

	public static func feature(example module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.feature(module).path + "/Example")
	}
}

// MARK: ProjectDescription.Path + Domain

extension ProjectDescription.Path {
	public static var domain: Self {
		return .relativeToRoot(ModulePath.domain(nil).path)
	}

	public static func domain(implementation module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.domain(module).path)
	}

	public static func domain(interface module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.domain(module).path + "/Interface")
	}

	public static func domain(tests module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.domain(module).path + "/Tests")
	}

	public static func domain(testing module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.domain(module).path + "/Testing")
	}
}

// MARK: ProjectDescription.Path + Data

extension ProjectDescription.Path {
	public static var data: Self {
		return .relativeToRoot(ModulePath.data(nil).path)
	}

	public static func data(implementation module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.data(module).path)
	}

	public static func data(interface module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.data(module).path + "/Interface")
	}

	public static func data(tests module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.data(module).path + "/Tests")
	}

	public static func data(testing module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.data(module).path + "/Testing")
	}
}

// MARK: ProjectDescription.Path + Core

extension ProjectDescription.Path {
	public static var core: Self {
		return .relativeToRoot(ModulePath.core(nil).path)
	}

	public static func core(implementation module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.core(module).path)
	}

	public static func core(interface module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.core(module).path + "/Interface")
	}

	public static func core(tests module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.core(module).path + "/Tests")
	}

	public static func core(testing module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.core(module).path + "/Testing")
	}
}

// MARK: ProjectDescription.Path + Shared

extension ProjectDescription.Path {
	public static var shared: Self {
		return .relativeToRoot(ModulePath.shared(nil).path)
	}

	public static func shared(implementation module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.shared(module).path)
	}

	public static func shared(interface module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.shared(module).path + "/Interface")
	}

	public static func shared(tests module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.shared(module).path + "/Tests")
	}

	public static func shared(testing module: ModuleType) -> Self {
		return .relativeToRoot(ModulePath.shared(module).path + "/Testing")
	}

}
