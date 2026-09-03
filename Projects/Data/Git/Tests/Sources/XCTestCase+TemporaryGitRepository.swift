import DomainGitInterface
import Foundation
import XCTest

extension XCTestCase {
	func makeTemporaryRepository(name: String = "GrovesProcessTests") throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		try runGit(arguments: ["-C", url.path, "init", "--quiet"])
		return url
	}

	func makeTemporaryDirectory(name: String = "GrovesProcessTestsDirectory") throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func runGit(arguments: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git"] + arguments
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw GitRepositoryError.invalidRepository }
	}
}
