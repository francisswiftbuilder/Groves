import Foundation

struct ProjectTarget {
	let name: String
	let layer: String
	let module: String
	let isInterface: Bool
}

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
	.appending(path: "Projects", directoryHint: .isDirectory)
let layers = ["Feature", "Core", "Domain", "Data", "Shared"]
let allowedLayers: [String: Set<String>] = [
	"App": ["App", "Feature", "Core", "Domain", "Data", "Shared"],
	"Feature": ["Feature", "Core", "Domain", "Shared"],
	"Core": ["Core", "Domain", "Shared"],
	"Domain": ["Domain", "Shared"],
	"Data": ["Data", "Core", "Domain", "Shared"],
	"Shared": ["Shared"],
]
var targetsBySourceDirectory: [String: ProjectTarget] = [:]
var targetsByName: [String: ProjectTarget] = [:]

func register(_ target: ProjectTarget, at directory: String) {
	guard fileManager.fileExists(atPath: directory) else { return }
	targetsBySourceDirectory[directory] = target
	targetsByName[target.name] = target
}

register(
	ProjectTarget(name: "App", layer: "App", module: "App", isInterface: false),
	at: rootURL.appending(path: "App/Sources").path
)

for layer in layers {
	let layerURL = rootURL.appending(path: layer, directoryHint: .isDirectory)
	let modules = (try? fileManager.contentsOfDirectory(atPath: layerURL.path)) ?? []
	for module in modules.sorted() {
		let moduleURL = layerURL.appending(path: module, directoryHint: .isDirectory)
		register(
			ProjectTarget(
				name: layer + module,
				layer: layer,
				module: module,
				isInterface: false
			),
			at: moduleURL.appending(path: "Sources").path
		)
		register(
			ProjectTarget(
				name: layer + module + "Interface",
				layer: layer,
				module: module,
				isInterface: true
			),
			at: moduleURL.appending(path: "Interface/Sources").path
		)
		guard fileManager.fileExists(atPath: moduleURL.appending(path: "Tests").path) else {
			continue
		}
		targetsByName[layer + module + "Tests"] = ProjectTarget(
			name: layer + module + "Tests",
			layer: layer,
			module: module,
			isInterface: false
		)
	}
}

if fileManager.fileExists(atPath: rootURL.appending(path: "App/UnitTests").path) {
	targetsByName["AppTests"] = ProjectTarget(
		name: "AppTests",
		layer: "App",
		module: "App",
		isInterface: false
	)
}

func owningTarget(of path: String) -> ProjectTarget? {
	targetsBySourceDirectory
		.filter { path.hasPrefix($0.key + "/") }
		.max { $0.key.count < $1.key.count }?
		.value
}

func violation(from source: ProjectTarget, to dependency: ProjectTarget) -> String? {
	guard allowedLayers[source.layer]?.contains(dependency.layer) == true else {
		return "\(source.layer) must not depend on \(dependency.layer)"
	}
	if source.isInterface, !dependency.isInterface {
		return "an interface target must not depend on an implementation target"
	}
	if source.layer == "Feature",
		dependency.layer == "Feature",
		source.module != dependency.module
	{
		return "a feature must not depend on another feature"
	}
	return nil
}

let importRegex = try NSRegularExpression(pattern: #"^import ([A-Za-z_][A-Za-z0-9_]*)"#)
let keys: [URLResourceKey] = [.isRegularFileKey]
let enumerator = fileManager.enumerator(
	at: rootURL,
	includingPropertiesForKeys: keys,
	options: [.skipsHiddenFiles]
)
var violations: Set<String> = []

while let fileURL = enumerator?.nextObject() as? URL {
	guard fileURL.pathExtension == "swift" else { continue }
	guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
	else {
		continue
	}
	guard let source = owningTarget(of: fileURL.path) else { continue }
	guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

	for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
		let value = String(line)
		let range = NSRange(value.startIndex..<value.endIndex, in: value)
		guard let match = importRegex.firstMatch(in: value, range: range),
			let nameRange = Range(match.range(at: 1), in: value),
			let dependency = targetsByName[String(value[nameRange])]
		else {
			continue
		}
		guard let reason = violation(from: source, to: dependency) else { continue }
		violations.insert("\(source.name) imports \(dependency.name): \(reason)")
	}
}

// An import is only half the contract: a target can also widen the graph by declaring a
// dependency it never imports, so the declarations are checked against the same rules.
let layerPrefixes = ["app": "App"].merging(
	layers.map { ($0.lowercased(), $0) },
	uniquingKeysWith: { first, _ in first }
)
let declarationRegex = try NSRegularExpression(
	pattern: #"^\s*public static var ([A-Za-z0-9_]+)Dependencies:"#
)
let dependencyRegex = try NSRegularExpression(
	pattern: #"^\s*\.([a-z]+)\((implements|interface): \.([A-Za-z0-9_]+)\)"#
)
let declarationsURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
	.appending(path: "Tuist/ProjectDescriptionHelpers/Dependencies.swift")

func capitalizingFirstLetter(_ value: String) -> String {
	guard let first = value.first else { return value }
	return first.uppercased() + value.dropFirst()
}

func capturedGroups(_ regex: NSRegularExpression, in value: String) -> [String]? {
	let range = NSRange(value.startIndex..<value.endIndex, in: value)
	guard let match = regex.firstMatch(in: value, range: range) else { return nil }
	return (1..<match.numberOfRanges).compactMap {
		Range(match.range(at: $0), in: value).map { range in String(value[range]) }
	}
}

if let contents = try? String(contentsOf: declarationsURL, encoding: .utf8) {
	var source: ProjectTarget?
	for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
		let value = String(line)
		if let groups = capturedGroups(declarationRegex, in: value) {
			source = targetsByName[capitalizingFirstLetter(groups[0])]
			continue
		}
		guard let source, let groups = capturedGroups(dependencyRegex, in: value) else { continue }
		guard let prefix = layerPrefixes[groups[0]] else { continue }
		let name =
			prefix + capitalizingFirstLetter(groups[2])
			+ (groups[1] == "interface" ? "Interface" : "")
		guard let dependency = targetsByName[name] else { continue }
		guard let reason = violation(from: source, to: dependency) else { continue }
		violations.insert("\(source.name) declares \(dependency.name): \(reason)")
	}
}

if violations.isEmpty {
	print("architecture-lint: Projects module dependencies follow the layer rules")
} else {
	for violation in violations.sorted() {
		FileHandle.standardError.write(Data("\(violation)\n".utf8))
	}
	exit(EXIT_FAILURE)
}
