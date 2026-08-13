import EnvironmentPlugin

nonisolated(unsafe) public let environment = ProjectEnvironment(
	name: "Trees",
	organizationName: "dev.trees",
	destinations: [.mac],
	deploymentTargets: .macOS("26.0"),
	baseSetting: baseSettings
)
