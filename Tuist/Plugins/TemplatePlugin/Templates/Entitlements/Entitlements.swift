import ProjectDescription

private let moduleAttribute = Template.Attribute.required("module")
private let appGroupIdAttribute = Template.Attribute.required("app_group_id")

let template = Template(
	description: "Example App entitlements with App Group",
	attributes: [
		moduleAttribute,
		appGroupIdAttribute,
	],
	items: [
		.file(
			path:
				"Projects/Feature/\(moduleAttribute)/Example/SupportFiles/Example\(moduleAttribute).entitlements",
			templatePath: "entitlements.stencil"
		)
	]
)
