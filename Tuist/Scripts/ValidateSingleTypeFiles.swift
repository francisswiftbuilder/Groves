import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
	.appending(path: "Projects", directoryHint: .isDirectory)
let declarationPattern =
	#"^(?:(?:public|package|internal|private|fileprivate|open|final|indirect|nonisolated|distributed) )*(?:class|struct|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#
let declarationRegex = try NSRegularExpression(pattern: declarationPattern)
let keys: [URLResourceKey] = [.isRegularFileKey]
let enumerator = fileManager.enumerator(
	at: rootURL,
	includingPropertiesForKeys: keys,
	options: [.skipsHiddenFiles]
)
var violations: [String] = []

while let fileURL = enumerator?.nextObject() as? URL {
	guard fileURL.pathExtension == "swift" else { continue }
	guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
	else {
		continue
	}
	guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
	if source.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first?
		.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("// AUTO-GENERATED") == true
	{
		continue
	}

	let declarations = source.split(
		separator: "\n",
		omittingEmptySubsequences: false
	).enumerated().compactMap { index, line -> String? in
		let value = String(line)
		let range = NSRange(value.startIndex..<value.endIndex, in: value)
		guard let match = declarationRegex.firstMatch(in: value, range: range),
			let nameRange = Range(match.range(at: 1), in: value)
		else {
			return nil
		}
		return "\(value[nameRange])@\(index + 1)"
	}

	if declarations.count > 1 {
		let path = fileURL.path.replacingOccurrences(
			of: rootURL.deletingLastPathComponent().path + "/", with: "")
		violations.append("\(path): \(declarations.joined(separator: ", "))")
	}
}

if violations.isEmpty {
	print("structure-lint: Projects Swift files contain at most one top-level type")
} else {
	for violation in violations.sorted() {
		FileHandle.standardError.write(Data("\(violation)\n".utf8))
	}
	exit(EXIT_FAILURE)
}
