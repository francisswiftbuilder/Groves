import Foundation

private let layers: [Layer] = [
	.app, .appExtension, .feature, .domain, .data, .core, .shared,
]

private let generationDir = "Tuist/ProjectDescriptionHelpers"
private let outputFile = "\(generationDir)/Modules.swift"

private enum Layer: String {
	case app = "App"
	case appExtension = "AppExtension"
	case feature = "Feature"
	case domain = "Domain"
	case data = "Data"
	case core = "Core"
	case shared = "Shared"

	var markTitle: String { "\(rawValue)Module" }
	var nestedEnumName: String { rawValue }
}

nonisolated(unsafe) private let fm = FileManager.default

private func scanModules(for layer: Layer) -> [String] {
	let base = "Projects/\(layer.rawValue)"
	guard let children = try? fm.contentsOfDirectory(atPath: base) else { return [] }
	return children.compactMap { name in
		guard !name.hasPrefix(".") else { return nil }
		var isDir: ObjCBool = false
		let full = base + "/" + name
		if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
			return name
		}
		return nil
	}
	.sorted()
}

private func scanExtensionGroups() -> [(String, [String])] {
	let base = "Projects/AppExtension"
	var isDir: ObjCBool = false
	guard fm.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else { return [] }
	guard let children = try? fm.contentsOfDirectory(atPath: base) else { return [] }
	var result: [(String, [String])] = []
	for name in children.sorted() {
		guard !name.hasPrefix(".") else { continue }
		let path = base + "/" + name
		var pIsDir: ObjCBool = false
		guard fm.fileExists(atPath: path, isDirectory: &pIsDir), pIsDir.boolValue else { continue }
		guard let subChildren = try? fm.contentsOfDirectory(atPath: path) else { continue }
		let subModules = subChildren.compactMap { subName -> String? in
			guard !subName.hasPrefix("."), subName != "Sources" else { return nil }
			let subPath = path + "/" + subName
			var sIsDir: ObjCBool = false
			guard fm.fileExists(atPath: subPath, isDirectory: &sIsDir), sIsDir.boolValue else {
				return nil
			}
			let sourcesPath = subPath + "/Sources"
			var srcIsDir: ObjCBool = false
			guard fm.fileExists(atPath: sourcesPath, isDirectory: &srcIsDir), srcIsDir.boolValue else {
				return nil
			}
			return subName
		}.sorted()
		if !subModules.isEmpty {
			result.append((name, subModules))
			continue
		}
		let selfSources = path + "/Sources"
		var selfIsDir: ObjCBool = false
		if fm.fileExists(atPath: selfSources, isDirectory: &selfIsDir), selfIsDir.boolValue {
			result.append((name, [name]))
		}
	}
	return result
}

private func swiftIdentifier(_ raw: String) -> String {
	var s = raw.map { c -> Character in
		(c.isLetter || c.isNumber) ? c : "_"
	}.reduce(into: "") { $0.append($1) }
	if let f = s.first, f.isNumber { s = "_" + s }
	while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
	return s
}

private func lowercasedFirst(_ s: String) -> String {
	guard let f = s.first else { return s }
	return f.lowercased() + s.dropFirst()
}

private struct LayerResult {
	let layer: Layer
	let cases: [ModuleCase]
	let groups: [(name: String, cases: [ModuleCase])]
	struct ModuleCase {
		let original: String
		let ident: String
	}
	init(layer: Layer, cases: [ModuleCase] = [], groups: [(String, [ModuleCase])] = []) {
		self.layer = layer
		self.cases = cases
		self.groups = groups
	}
}

private func buildLayerResult(layer: Layer, names: [String]) -> LayerResult {
	LayerResult(layer: layer, cases: names.map { .init(original: $0, ident: swiftIdentifier($0)) })
}

private func buildExtensionLayerResult(groups: [(name: String, modules: [String])]) -> LayerResult {
	let g = groups.map { (name, modules) in
		let cases = modules.map { LayerResult.ModuleCase(original: $0, ident: swiftIdentifier($0)) }
		return (name: name, cases: cases)
	}
	return LayerResult(layer: .appExtension, cases: [], groups: g)
}

private func emitHeader() -> String {
	[
		"// AUTO-GENERATED. DO NOT EDIT.",
		"// Source of truth: directory structure under Projects/<Layer>/<Module>/Sources",
		"import Foundation",
		"import ProjectDescription",
		"import TargetPlugin",
	].joined(separator: "\n")
}

private func emitRootModule(hasAppSources: Bool) -> String {
	guard hasAppSources else { return "public enum Module { }" }
	return """
		public enum Module: String, ModuleAppType {
			case App
			public var name: String { rawValue }
		}
		"""
}

private func protocolName(for layer: Layer) -> String {
	switch layer {
	case .app: return "ModuleAppType"
	case .feature: return "ModuleFeatureType"
	case .domain: return "ModuleDomainType"
	case .data: return "ModuleDataType"
	case .core: return "ModuleCoreType"
	case .shared: return "ModuleSharedType"
	case .appExtension: return "ModuleAppExtensionType"
	}
}

private func emitLayerEnum(_ lr: LayerResult) -> String {
	if lr.layer == .appExtension {
		guard !lr.groups.isEmpty else { return "" }
		var lines: [String] = []
		lines.append("public extension Module {")
		lines.append(
			"  enum \(lr.layer.nestedEnumName): String, CaseIterable, \(protocolName(for: lr.layer)) {")
		for g in lr.groups {
			if g.cases.count == 1 {
				let mc = g.cases[0]
				if mc.ident == swiftIdentifier(g.name) {
					if mc.ident == mc.original {
						lines.append("    case \(mc.ident)")
					} else {
						lines.append("    case \(mc.ident) = \"\(mc.original)\"")
					}
				} else {
					let enumName = swiftIdentifier(g.name)
					lines.append("  enum \(enumName): String, CaseIterable, \(protocolName(for: lr.layer)) {")
					if mc.ident == mc.original {
						lines.append("      case \(mc.ident)")
					} else {
						lines.append("      case \(mc.ident) = \"\(mc.original)\"")
					}
					lines.append("      public var name: String { rawValue }")
					lines.append("    }")
				}
			} else {
				let enumName = swiftIdentifier(g.name)
				lines.append("  enum \(enumName): String, CaseIterable, \(protocolName(for: lr.layer)) {")
				for mc in g.cases {
					if mc.ident == mc.original {
						lines.append("      case \(mc.ident)")
					} else {
						lines.append("      case \(mc.ident) = \"\(mc.original)\"")
					}
				}
				lines.append("      public var name: String { rawValue }")
				lines.append("    }")
			}
		}
		lines.append("    public var name: String { rawValue }")
		lines.append("  }")
		lines.append("}")
		return lines.joined(separator: "\n")
	}

	guard !lr.cases.isEmpty else { return "" }
	var lines: [String] = []
	let enumName = lr.layer.nestedEnumName
	let proto = protocolName(for: lr.layer)
	lines.append("public extension Module {")
	lines.append("  enum \(enumName): String, CaseIterable, \(proto) {")
	for mc in lr.cases {
		if mc.ident == mc.original {
			lines.append("    case \(mc.ident)")
		} else {
			lines.append("    case \(mc.ident) = \"\(mc.original)\"")
		}
	}
	lines.append("    public var name: String { rawValue }")
	lines.append("  }")
	lines.append("}")
	return lines.joined(separator: "\n")
}

private func emitShortcutExtensions(_ results: [LayerResult], hasAppSources: Bool) -> String {
	var parts: [String] = []
	if hasAppSources {
		parts.append(
			"""
			extension ModuleAppType where Self == Module {
				public static var app: Module { Module.App }
			}
			""")
	}
	for lr in results {
		if lr.layer == .appExtension {
			guard !lr.groups.isEmpty else { continue }
			var lines: [String] = []
			lines.append("extension ModuleAppExtensionType where Self == Module.AppExtension {")
			for g in lr.groups {
				let grpIdent = swiftIdentifier(g.name)
				if g.cases.count == 1 {
					let mc = g.cases[0]
					if mc.ident == grpIdent {
						lines.append(
							"  public static var \(lowercasedFirst(mc.ident)): Module.AppExtension { .\(mc.ident) }"
						)
					} else {
						lines.append(
							"  public static var \(lowercasedFirst(mc.ident)): Module.AppExtension.\(grpIdent) { .\(mc.ident) }"
						)
					}
				} else {
					for mc in g.cases {
						lines.append(
							"  public static var \(lowercasedFirst(mc.ident)): Module.AppExtension.\(grpIdent) { .\(mc.ident) }"
						)
					}
				}
			}
			lines.append("}")
			parts.append(lines.joined(separator: "\n"))
			continue
		}

		guard !lr.cases.isEmpty else { continue }
		let proto = protocolName(for: lr.layer)
		let enumName = lr.layer.nestedEnumName
		var lines: [String] = []
		lines.append("extension \(proto) where Self == Module.\(enumName) {")
		for mc in lr.cases {
			lines.append(
				"  public static var \(lowercasedFirst(mc.ident)): Module.\(enumName) { Module.\(enumName).\(mc.ident) }"
			)
		}
		lines.append("}")
		parts.append(lines.joined(separator: "\n"))
	}
	return parts.joined(separator: "\n\n")
}

private func generateFile(results: [LayerResult], hasAppSources: Bool) -> String {
	let header = emitHeader()
	let root = emitRootModule(hasAppSources: hasAppSources)
	let enums = results.map { emitLayerEnum($0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
	let shortcuts = emitShortcutExtensions(results, hasAppSources: hasAppSources)
	return [header, root, enums, shortcuts].filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
}

private func run() {
	var scanned: [LayerResult] = []

	let extensionGroups = scanExtensionGroups()
	if !extensionGroups.isEmpty {
		scanned.append(buildExtensionLayerResult(groups: extensionGroups))
	} else {
		let extFallback = scanModules(for: .appExtension)
		if !extFallback.isEmpty {
			scanned.append(buildLayerResult(layer: .appExtension, names: extFallback))
		}
	}

	for layer in layers where layer != .app && layer != .appExtension {
		let names = scanModules(for: layer)
		if !names.isEmpty {
			scanned.append(buildLayerResult(layer: layer, names: names))
		}
	}

	var isDir: ObjCBool = false
	let hasAppSources =
		fm.fileExists(atPath: "Projects/App/Sources", isDirectory: &isDir) && isDir.boolValue

	if !fm.fileExists(atPath: generationDir) {
		try? fm.createDirectory(atPath: generationDir, withIntermediateDirectories: true)
	}

	let content = generateFile(results: scanned, hasAppSources: hasAppSources)
	let normalized = content.replacingOccurrences(of: "\t", with: "  ")

	if fm.fileExists(atPath: outputFile) {
		try? fm.removeItem(atPath: outputFile)
	}

	do {
		try normalized.write(toFile: outputFile, atomically: true, encoding: .utf8)
		fputs("✅ Generated `\(outputFile)`\n", stderr)
		for module in scanned {
			if module.layer == .appExtension {
				if !module.groups.isEmpty {
					fputs(
						"  - AppExtension groups: \(module.groups.map { "\($0.name): \($0.cases.count)" }.joined(separator: ", "))\n",
						stderr)
				} else {
					fputs("  - AppExtension: \(module.cases.count) modules\n", stderr)
				}
			} else {
				fputs("  - \(module.layer.rawValue): \(module.cases.count) modules\n", stderr)
			}
		}
		if hasAppSources {
			fputs("  - App: included\n", stderr)
		} else {
			fputs("  - App: skipped (Projects/App/Sources not found)\n", stderr)
		}
	} catch {
		fputs("❌ Failed writing file: \(error)\n", stderr)
		exit(1)
	}
}

run()
