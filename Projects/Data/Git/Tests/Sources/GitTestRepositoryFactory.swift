import DomainGitInterface
import Foundation

enum GitTestRepositoryFactory {
	static func makeRepository(name: String = "GrovesProcessTests") throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		try runGit(arguments: ["-C", url.path, "init", "--quiet"])
		return url
	}

	static func makeDirectory(name: String = "GrovesProcessTestsDirectory") throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private static func runGit(arguments: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git"] + arguments
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw GitRepositoryError.invalidRepository }
	}
}
