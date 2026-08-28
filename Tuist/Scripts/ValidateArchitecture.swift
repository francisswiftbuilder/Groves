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
let workspaceCompositionTargets: Set<String> = ["FeatureRepository"]

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
	}
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
		source.module != dependency.module,
		!workspaceCompositionTargets.contains(source.name)
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

if violations.isEmpty {
	print("architecture-lint: Projects module dependencies follow the layer rules")
} else {
	for violation in violations.sorted() {
		FileHandle.standardError.write(Data("\(violation)\n".utf8))
	}
	exit(EXIT_FAILURE)
}
