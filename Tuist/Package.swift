// swift-tools-version: 6.0
import Foundation
import PackageDescription

#if TUIST
	import struct ProjectDescription.PackageSettings
	import ConfigurationPlugin

	let packageSettings = PackageSettings(
		baseSettings: .settings(
			configurations: ConfigurationType.configurations()
		)
	)
#endif

let package = Package(
	name: "Trees",
	platforms: [.macOS("26.0")],
	products: [],
	dependencies: [],
	targets: []
)
