import ProjectDescription

private let layerAttribute = Template.Attribute.required("layer")
private let nameAttribute = Template.Attribute.required("name")

private let template = Template(
	description: "A template for a new module's testing target",
	attributes: [
		layerAttribute,
		nameAttribute,
	],
	items: [
		.string(
			path:
				"Projects/\(layerAttribute)/\(nameAttribute)/Testing/Sources/\(nameAttribute)Testing.swift",
			contents: "import Foundation\n"
		)
	]
)
