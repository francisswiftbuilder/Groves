import DomainGitInterface
import Foundation

struct GitCommandResult: Sendable {
	let standardOutput: String
	let standardError: String
}

actor GitProcessRunner {
	func requestRun(
		arguments: [String],
		at repositoryURL: URL,
		standardInput: String? = nil,
		acceptedTerminationStatuses: Set<Int32> = [0]
	) async throws -> GitCommandResult {
		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory
			.appendingPathComponent("Trees-\(UUID().uuidString)", isDirectory: true)
		let standardOutputURL = temporaryDirectory.appendingPathComponent("stdout")
		let standardErrorURL = temporaryDirectory.appendingPathComponent("stderr")
		let standardInputURL = temporaryDirectory.appendingPathComponent("stdin")

		try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		fileManager.createFile(atPath: standardOutputURL.path, contents: nil)
		fileManager.createFile(atPath: standardErrorURL.path, contents: nil)

		defer {
			try? fileManager.removeItem(at: temporaryDirectory)
		}

		let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
		let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
		let standardInputHandle: FileHandle?
		if let standardInput {
			try Data(standardInput.utf8).write(to: standardInputURL)
			standardInputHandle = try FileHandle(forReadingFrom: standardInputURL)
		} else {
			standardInputHandle = nil
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", repositoryURL.path] + arguments
		process.standardOutput = standardOutputHandle
		process.standardError = standardErrorHandle
		process.standardInput = standardInputHandle

		let terminationStatus = try await requestTerminationStatus(
			for: process,
			standardInputHandle: standardInputHandle,
			standardOutputHandle: standardOutputHandle,
			standardErrorHandle: standardErrorHandle
		)
		let standardOutputData = try Data(contentsOf: standardOutputURL)
		let standardErrorData = try Data(contentsOf: standardErrorURL)
		let standardOutput = String(decoding: standardOutputData, as: UTF8.self)
		let standardError = String(decoding: standardErrorData, as: UTF8.self)

		guard acceptedTerminationStatuses.contains(terminationStatus) else {
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
		standardInputHandle: FileHandle?,
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
					standardInputHandle?.closeFile()
					standardOutputHandle.closeFile()
					standardErrorHandle.closeFile()
				} catch {
					standardInputHandle?.closeFile()
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
