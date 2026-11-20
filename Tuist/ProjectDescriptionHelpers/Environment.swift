import EnvironmentPlugin

nonisolated(unsafe) public let environment = ProjectEnvironment(
	name: "Pluminon",
	organizationName: "com.francisswiftbuilder.pluminon",
	destinations: [.mac],
	deploymentTargets: .macOS("26.0"),
	baseSetting: baseSettings
)
