import EnvironmentPlugin

nonisolated(unsafe) public let environment = ProjectEnvironment(
	name: "Groves",
	organizationName: "io.github.francisswiftbuilder.Groves",
	destinations: [.mac],
	deploymentTargets: .macOS("26.0"),
	baseSetting: baseSettings
)
