import Foundation

enum LayerType: String, CaseIterable {
	case feature = "Feature"
	case domain = "Domain"
	case data = "Data"
	case core = "Core"
	case shared = "Shared"

	init?(number: Int) {
		switch number {
		case 1: self = .feature
		case 2: self = .domain
		case 3: self = .data
		case 4: self = .core
		case 5: self = .shared
		default: return nil
		}
	}
}

enum MicroTargetType: String {
	case interface = "Interface"
	case sources = "Sources"
	case testing = "Testing"
	case tests = "Tests"
	case example = "Example"
}

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath + "/"
let bash = Bash()

@discardableResult
func ask(_ prompt: String) -> String {
	print(prompt, terminator: " : ")
	return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func makeDirectory(path: String) {
	try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func makeProjectDirectory(layer: LayerType, module: String) {
	makeDirectory(path: currentPath + "Projects/\(layer.rawValue)/\(module)")
}

func makeScaffold(target: MicroTargetType, layer: LayerType, module: String) {
	_ = try? bash.run(
		commandName: "tuist",
		arguments: ["scaffold", target.rawValue, "--name", module, "--layer", layer.rawValue]
	)
}

func makeProjectFile(layer: LayerType, module: String, hasTests: Bool, hasExample: Bool) {
	let projectFilePath = currentPath + "Projects/\(layer.rawValue)/\(module)/Project.swift"
	guard !fileManager.fileExists(atPath: projectFilePath) else {
		print("ℹ️ Project.swift already exists. Skipping file generation.")
		return
	}

	let projectName = "\(layer.rawValue)\(module)"
	let targetPrefix = layer.rawValue.lowercased()
	var targets = [".\(targetPrefix)\(module)", ".\(targetPrefix)\(module)Interface"]
	if hasTests {
		targets.append(contentsOf: [
			".\(targetPrefix)\(module)Tests",
			".\(targetPrefix)\(module)Testing",
		])
	}
	if layer == .feature && hasExample {
		targets.append(".\(targetPrefix)\(module)Example")
	}

	let targetsBlock =
		targets
		.map { "\t\t\($0)," }
		.joined(separator: "\n")

	var schemeDecls: [String] = []
	if layer == .feature && hasExample {
		schemeDecls.append(".example\(module)Scheme")
	}
	if hasTests {
		let testsTarget = ".\(targetPrefix)\(module)Tests"
		schemeDecls.append(
			"""
			.scheme(
				name: "\(projectName)",
				shared: true,
				buildAction: .buildAction(targets: [.\(targetPrefix)\(module)]),
				testAction: .targets(
					[.testableTarget(target: \(testsTarget))],
					configuration: .debug,
					options: .options(coverage: true)
				)
			)
			"""
		)
	}

	let schemesBlock: String = {
		guard !schemeDecls.isEmpty else { return "\tschemes: []" }
		let suffix = schemeDecls.count > 1 ? "," : ""
		let body = schemeDecls.enumerated()
			.map { index, decl -> String in
				let indented =
					decl
					.split(separator: "\n", omittingEmptySubsequences: false)
					.map { "\t\t\($0)" }
					.joined(separator: "\n")
				return indented + (index == schemeDecls.count - 1 ? suffix : ",")
			}
			.joined(separator: "\n")
		return "\tschemes: [\n\(body)\n\t]"
	}()

	let fileContents = """
		import ConfigurationPlugin
		import ProjectDescription
		import ProjectDescriptionHelpers

		let project = Project(
			name: \"\(projectName)\",
			options: .options(
				automaticSchemesOptions: .disabled,
				textSettings: .textSettings(
					usesTabs: true,
					indentWidth: 2,
					tabWidth: 2
				)
			),
			settings: .settings(
				base: baseSettings,
				configurations: ConfigurationType.configurations()
			),
			targets: [
		\(targetsBlock)
			],
		\(schemesBlock)
		)

		"""

	do {
		try fileContents.write(toFile: projectFilePath, atomically: true, encoding: .utf8)
		print("🆕 Created Project.swift at Projects/\(layer.rawValue)/\(module)")
	} catch {
		print("⚠️ Failed to write Project.swift: \(error)")
	}
}

func registerModule() {
	let layerInput: String = ask(
		"\n1.Feature \n2.Domain \n3.Data \n4.Core \n5.Shared\nEnter layer number ")
	guard
		let layerInt = Int(layerInput),
		let layer = LayerType(number: layerInt)
	else {
		print("Invalid layer")
		exit(1)
	}
	let module = ask("Enter module name")
	guard !module.isEmpty else {
		print("Empty module")
		exit(1)
	}
	let hasTests = ask("Has Tests? (y/n, default n)").lowercased() == "y"
	let hasExample = (layer == .feature) && ask("Has Example? (y/n, default n)").lowercased() == "y"

	makeProjectDirectory(layer: layer, module: module)
	makeScaffold(target: .interface, layer: layer, module: module)
	makeScaffold(target: .sources, layer: layer, module: module)
	if hasTests {
		makeScaffold(target: .testing, layer: layer, module: module)
		makeScaffold(target: .tests, layer: layer, module: module)
	}
	if hasExample {
		makeScaffold(target: .example, layer: layer, module: module)
	}

	makeProjectFile(layer: layer, module: module, hasTests: hasTests, hasExample: hasExample)

	print("------------------------------------------------------------------")
	print("Layer: \(layer.rawValue)")
	print("Module: \(module)")
	print("Tests: \(hasTests), Example: \(hasExample)")
	print("✅ Module scaffold 완료.")
	print("------------------------------------------------------------------")
}

registerModule()

protocol CommandExecuting {
	func run(commandName: String, arguments: [String]) throws -> String
}
enum BashError: Error { case commandNotFound(name: String) }
struct Bash: CommandExecuting {
	func run(commandName: String, arguments: [String] = []) throws -> String {
		try run(resolve(commandName), with: arguments)
	}
	private func resolve(_ command: String) throws -> String {
		guard let which = try? run("/bin/bash", with: ["-l", "-c", "which \(command)"]) else {
			throw BashError.commandNotFound(name: command)
		}
		return which.trimmingCharacters(in: .whitespacesAndNewlines)
	}
	private func run(_ command: String, with arguments: [String]) throws -> String {
		let p = Process()
		p.launchPath = command
		p.arguments = arguments
		let pipe = Pipe()
		p.standardOutput = pipe
		p.launch()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(decoding: data, as: UTF8.self)
	}
}
