import Foundation

enum LayerType: String, CaseIterable {
	case Feature, Domain, Data, Core, Shared

	init?(number: Int) {
		switch number {
		case 1: self = .Feature
		case 2: self = .Domain
		case 3: self = .Data
		case 4: self = .Core
		case 5: self = .Shared
		default: return nil
		}
	}
}

enum MicroTargetType: String { case Interface, Sources, Testing, Tests, Example }

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
	if layer == .Feature && hasExample {
		targets.append(".\(targetPrefix)\(module)Example")
	}

	let targetsBlock =
		targets
		.map { "    \($0)," }
		.joined(separator: "\n")

	let schemesBlock: String = {
		guard layer == .Feature && hasExample else { return "  schemes: []" }
		return """
			  schemes: [
			    .example\(module)Scheme,
			  ]
			"""
	}()

	let fileContents = """
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
		    configurations: configurations
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
	let hasExample = (layer == .Feature) && ask("Has Example? (y/n, default n)").lowercased() == "y"

	makeProjectDirectory(layer: layer, module: module)
	makeScaffold(target: .Interface, layer: layer, module: module)
	makeScaffold(target: .Sources, layer: layer, module: module)
	if hasTests {
		makeScaffold(target: .Testing, layer: layer, module: module)
		makeScaffold(target: .Tests, layer: layer, module: module)
	}
	if hasExample {
		makeScaffold(target: .Example, layer: layer, module: module)
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
