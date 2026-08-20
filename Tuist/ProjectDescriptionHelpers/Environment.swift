import EnvironmentPlugin

nonisolated(unsafe) public let environment = ProjectEnvironment(
	name: "Trees",
	organizationName: "io.github.francisswiftbuilder.Trees",
	destinations: [.mac],
	deploymentTargets: .macOS("26.0"),
	baseSetting: baseSettings
)
