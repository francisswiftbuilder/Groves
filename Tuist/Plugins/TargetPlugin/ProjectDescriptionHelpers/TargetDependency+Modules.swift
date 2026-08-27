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
		let modulePath = ModulePath.feature(module)
		return .project(target: modulePath.name, path: .relativeToRoot(modulePath.path))
	}

	public static func feature(interface module: ModuleFeatureType) -> Self {
		let modulePath = ModulePath.feature(module)
		return .project(target: modulePath.interface, path: .relativeToRoot(modulePath.path))
	}

	public static func feature(tests module: ModuleFeatureType) -> Self {
		let modulePath = ModulePath.feature(module)
		return .project(target: modulePath.tests, path: .relativeToRoot(modulePath.path))
	}

	public static func feature(testing module: ModuleFeatureType) -> Self {
		let modulePath = ModulePath.feature(module)
		return .project(target: modulePath.testing, path: .relativeToRoot(modulePath.path))
	}

	public static func feature(example module: ModuleFeatureType) -> Self {
		let modulePath = ModulePath.feature(module)
		return .project(target: modulePath.example, path: .relativeToRoot(modulePath.path))
	}
}

// MARK: TargetDependency + Domain

extension TargetDependency {
	public static func domain(implements module: ModuleDomainType? = nil) -> Self {
		let modulePath = ModulePath.domain(module)
		return .project(target: modulePath.name, path: .relativeToRoot(modulePath.path))
	}

	public static func domain(interface module: ModuleDomainType) -> Self {
		let modulePath = ModulePath.domain(module)
		return .project(target: modulePath.interface, path: .relativeToRoot(modulePath.path))
	}

	public static func domain(tests module: ModuleDomainType) -> Self {
		let modulePath = ModulePath.domain(module)
		return .project(target: modulePath.tests, path: .relativeToRoot(modulePath.path))
	}

	public static func domain(testing module: ModuleDomainType) -> Self {
		let modulePath = ModulePath.domain(module)
		return .project(target: modulePath.testing, path: .relativeToRoot(modulePath.path))
	}
}

// MARK: TargetDependency + Data

extension TargetDependency {
	public static func data(implements module: ModuleDataType? = nil) -> Self {
		let modulePath = ModulePath.data(module)
		return .project(target: modulePath.name, path: .relativeToRoot(modulePath.path))
	}

	public static func data(interface module: ModuleDataType) -> Self {
		let modulePath = ModulePath.data(module)
		return .project(target: modulePath.interface, path: .relativeToRoot(modulePath.path))
	}

	public static func data(tests module: ModuleDataType) -> Self {
		let modulePath = ModulePath.data(module)
		return .project(target: modulePath.tests, path: .relativeToRoot(modulePath.path))
	}

	public static func data(testing module: ModuleDataType) -> Self {
		let modulePath = ModulePath.data(module)
		return .project(target: modulePath.testing, path: .relativeToRoot(modulePath.path))
	}
}

// MARK: TargetDependency + Core

extension TargetDependency {
	public static func core(implements module: ModuleCoreType? = nil) -> Self {
		let modulePath = ModulePath.core(module)
		return .project(target: modulePath.name, path: .relativeToRoot(modulePath.path))
	}

	public static func core(interface module: ModuleCoreType) -> Self {
		let modulePath = ModulePath.core(module)
		return .project(target: modulePath.interface, path: .relativeToRoot(modulePath.path))
	}

	public static func core(tests module: ModuleCoreType) -> Self {
		let modulePath = ModulePath.core(module)
		return .project(target: modulePath.tests, path: .relativeToRoot(modulePath.path))
	}

	public static func core(testing module: ModuleCoreType) -> Self {
		let modulePath = ModulePath.core(module)
		return .project(target: modulePath.testing, path: .relativeToRoot(modulePath.path))
	}
}

// MARK: TargetDependency + Shared

extension TargetDependency {
	public static func shared(implements module: ModuleSharedType? = nil) -> Self {
		let modulePath = ModulePath.shared(module)
		return .project(target: modulePath.name, path: .relativeToRoot(modulePath.path))
	}

	public static func shared(interface module: ModuleSharedType) -> Self {
		let modulePath = ModulePath.shared(module)
		return .project(target: modulePath.interface, path: .relativeToRoot(modulePath.path))
	}
}
