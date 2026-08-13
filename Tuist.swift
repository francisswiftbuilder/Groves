import ProjectDescription

let tuist = Tuist(
	project: .tuist(
		plugins: [
			.local(path: "../Tuist/Plugins/ConfigurationPlugin"),
			.local(path: "../Tuist/Plugins/TargetPlugin"),
			.local(path: "../Tuist/Plugins/EnvironmentPlugin"),
			.local(path: "../Tuist/Plugins/TemplatePlugin"),
		]
	)
)
