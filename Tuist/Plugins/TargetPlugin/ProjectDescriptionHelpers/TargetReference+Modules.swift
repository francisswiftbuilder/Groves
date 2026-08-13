import Foundation
import ProjectDescription

// MARK: TargetReference + App

extension TargetReference {
	public static func app(implements module: ModuleAppType? = nil) -> Self {
		return .project(path: .app, target: ModulePath.app.name)
	}
}

// MARK: TargetReference + Extension

extension TargetReference {
	public static func appExtension(implements module: ModuleAppExtensionType? = nil) -> Self {
		return .target(ModulePath.appExtension(module).name)
	}
}

// MARK: TargetReference + Feature

extension TargetReference {
	public static func feature(implements module: ModuleFeatureType? = nil) -> Self {
		return .target(ModulePath.feature(module).name)
	}

	public static func feature(interface module: ModuleFeatureType) -> Self {
		return .target(ModulePath.feature(module).interface)
	}

	public static func feature(tests module: ModuleFeatureType) -> Self {
		return .target(ModulePath.feature(module).tests)
	}

	public static func feature(testing module: ModuleFeatureType) -> Self {
		return .target(ModulePath.feature(module).testing)
	}

	public static func feature(example module: ModuleFeatureType) -> Self {
		return .target(ModulePath.feature(module).example)
	}
}

// MARK: TargetReference + Domain

extension TargetReference {
	public static func domain(implements module: ModuleDomainType? = nil) -> Self {
		return .target(ModulePath.domain(module).name)
	}

	public static func domain(interface module: ModuleDomainType) -> Self {
		return .target(ModulePath.domain(module).interface)
	}

	public static func domain(tests module: ModuleDomainType) -> Self {
		return .target(ModulePath.domain(module).tests)
	}

	public static func domain(testing module: ModuleDomainType) -> Self {
		return .target(ModulePath.domain(module).testing)
	}
}

// MARK: TargetReference + Data

extension TargetReference {
	public static func data(implements module: ModuleDataType? = nil) -> Self {
		return .target(ModulePath.data(module).name)
	}

	public static func data(interface module: ModuleDataType) -> Self {
		return .target(ModulePath.data(module).interface)
	}

	public static func data(tests module: ModuleDataType) -> Self {
		return .target(ModulePath.data(module).tests)
	}

	public static func data(testing module: ModuleDataType) -> Self {
		return .target(ModulePath.data(module).testing)
	}
}

// MARK: TargetReference + Core

extension TargetReference {
	public static func core(implements module: ModuleCoreType? = nil) -> Self {
		return .target(ModulePath.core(module).name)
	}

	public static func core(interface module: ModuleCoreType) -> Self {
		return .target(ModulePath.core(module).interface)
	}

	public static func core(tests module: ModuleCoreType) -> Self {
		return .target(ModulePath.core(module).tests)
	}

	public static func core(testing module: ModuleCoreType) -> Self {
		return .target(ModulePath.core(module).testing)
	}
}

// MARK: TargetReference + Shared

extension TargetReference {
	public static func shared(implements module: ModuleSharedType? = nil) -> Self {
		return .target(ModulePath.shared(module).name)
	}

	public static func shared(interface module: ModuleSharedType) -> Self {
		return .target(ModulePath.shared(module).interface)
	}
}
