import Foundation
import ProjectDescription

// MARK: TargetDependency + App

extension TargetDependency {
	public static func app(implements module: ModuleAppType? = nil) -> Self {
		return .project(target: ModulePath.app.name, path: .app)
	}
}

// MARK: TargetDependency + Extension

extension TargetDependency {
	public static func appExtension(implements module: ModuleAppExtensionType? = nil) -> Self {
		return .target(name: ModulePath.appExtension(module).name)
	}
}

// MARK: TargetDependency + Feature

extension TargetDependency {
	public static func feature(implements module: ModuleFeatureType? = nil) -> Self {
		return .target(name: ModulePath.feature(module).name)
	}

	public static func feature(interface module: ModuleFeatureType) -> Self {
		return .target(name: ModulePath.feature(module).interface)
	}

	public static func feature(tests module: ModuleFeatureType) -> Self {
		return .target(name: ModulePath.feature(module).tests)
	}

	public static func feature(testing module: ModuleFeatureType) -> Self {
		return .target(name: ModulePath.feature(module).testing)
	}

	public static func feature(example module: ModuleFeatureType) -> Self {
		return .target(name: ModulePath.feature(module).example)
	}
}

// MARK: TargetDependency + Domain

extension TargetDependency {
	public static func domain(implements module: ModuleDomainType? = nil) -> Self {
		return .target(name: ModulePath.domain(module).name)
	}

	public static func domain(interface module: ModuleDomainType) -> Self {
		return .target(name: ModulePath.domain(module).interface)
	}

	public static func domain(tests module: ModuleDomainType) -> Self {
		return .target(name: ModulePath.domain(module).tests)
	}

	public static func domain(testing module: ModuleDomainType) -> Self {
		return .target(name: ModulePath.domain(module).testing)
	}
}

// MARK: TargetDependency + Data

extension TargetDependency {
	public static func data(implements module: ModuleDataType? = nil) -> Self {
		return .target(name: ModulePath.data(module).name)
	}

	public static func data(interface module: ModuleDataType) -> Self {
		return .target(name: ModulePath.data(module).interface)
	}

	public static func data(tests module: ModuleDataType) -> Self {
		return .target(name: ModulePath.data(module).tests)
	}

	public static func data(testing module: ModuleDataType) -> Self {
		return .target(name: ModulePath.data(module).testing)
	}
}

// MARK: TargetDependency + Core

extension TargetDependency {
	public static func core(implements module: ModuleCoreType? = nil) -> Self {
		return .target(name: ModulePath.core(module).name)
	}

	public static func core(interface module: ModuleCoreType) -> Self {
		return .target(name: ModulePath.core(module).interface)
	}

	public static func core(tests module: ModuleCoreType) -> Self {
		return .target(name: ModulePath.core(module).tests)
	}

	public static func core(testing module: ModuleCoreType) -> Self {
		return .target(name: ModulePath.core(module).testing)
	}
}

// MARK: TargetDependency + Shared

extension TargetDependency {
	public static func shared(implements module: ModuleSharedType? = nil) -> Self {
		return .target(name: ModulePath.shared(module).name)
	}

	public static func shared(interface module: ModuleSharedType) -> Self {
		return .target(name: ModulePath.shared(module).interface)
	}
}

extension TargetDependency {
	public static func module<Module>(feature module: Module) -> TargetDependency
	where Module: ModuleFeatureType {
		.project(target: "Feature\(module.name)", path: .feature(implementation: module))
	}

	public static func module<Module>(domain module: Module) -> TargetDependency
	where Module: ModuleDomainType {
		.project(target: "Domain\(module.name)", path: .domain(implementation: module))
	}

	public static func module<Module>(data module: Module) -> TargetDependency
	where Module: ModuleDataType {
		.project(target: "Data\(module.name)", path: .data(implementation: module))
	}

	public static func module<Module>(core module: Module) -> TargetDependency
	where Module: ModuleCoreType {
		.project(target: "Core\(module.name)", path: .core(implementation: module))
	}

	public static func module<Module>(shared module: Module) -> TargetDependency
	where Module: ModuleSharedType {
		.project(target: "Shared\(module.name)", path: .shared(implementation: module))
	}
}
