import DomainGitInterface
import Foundation

struct GitCommandResult: Sendable {
	let standardOutput: String
	let standardError: String
}

actor GitProcessRunner {
	func requestRun(arguments: [String], at repositoryURL: URL) async throws -> GitCommandResult {
		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory
			.appendingPathComponent("Trees-\(UUID().uuidString)", isDirectory: true)
		let standardOutputURL = temporaryDirectory.appendingPathComponent("stdout")
		let standardErrorURL = temporaryDirectory.appendingPathComponent("stderr")

		try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		fileManager.createFile(atPath: standardOutputURL.path, contents: nil)
		fileManager.createFile(atPath: standardErrorURL.path, contents: nil)

		defer {
			try? fileManager.removeItem(at: temporaryDirectory)
		}

		let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
		let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", repositoryURL.path] + arguments
		process.standardOutput = standardOutputHandle
		process.standardError = standardErrorHandle

		let terminationStatus = try await requestTerminationStatus(
			for: process,
			standardOutputHandle: standardOutputHandle,
			standardErrorHandle: standardErrorHandle
		)
		let standardOutputData = try Data(contentsOf: standardOutputURL)
		let standardErrorData = try Data(contentsOf: standardErrorURL)
		let standardOutput = String(decoding: standardOutputData, as: UTF8.self)
		let standardError = String(decoding: standardErrorData, as: UTF8.self)

		guard terminationStatus == 0 else {
			if Task.isCancelled {
				throw CancellationError()
			}
			throw GitRepositoryError.commandFailed(
				standardError.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}

		return GitCommandResult(standardOutput: standardOutput, standardError: standardError)
	}

	private func requestTerminationStatus(
		for process: Process,
		standardOutputHandle: FileHandle,
		standardErrorHandle: FileHandle
	) async throws -> Int32 {
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				process.terminationHandler = { process in
					continuation.resume(returning: process.terminationStatus)
				}

				do {
					try process.run()
					standardOutputHandle.closeFile()
					standardErrorHandle.closeFile()
				} catch {
					standardOutputHandle.closeFile()
					standardErrorHandle.closeFile()
					continuation.resume(throwing: error)
				}
			}
		} onCancel: {
			if process.isRunning {
				process.terminate()
			}
		}
	}
}
