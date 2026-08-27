import ProjectDescription

let tuist = Tuist(
	project: .tuist(
		plugins: [
			.git(
				url: "https://github.com/francisswiftbuilder/tuist_template.git",
				tag: "1.0.0",
				directory: "Tuist/Plugins/ConfigurationPlugin"
			),
			.git(
				url: "https://github.com/francisswiftbuilder/tuist_template.git",
				tag: "1.0.0",
				directory: "Tuist/Plugins/TargetPlugin"
			),
			.git(
				url: "https://github.com/francisswiftbuilder/tuist_template.git",
				tag: "1.0.0",
				directory: "Tuist/Plugins/EnvironmentPlugin"
			),
			.git(
				url: "https://github.com/francisswiftbuilder/tuist_template.git",
				tag: "1.0.0",
				directory: "Tuist/Plugins/TemplatePlugin"
			),
		]
	)
)
