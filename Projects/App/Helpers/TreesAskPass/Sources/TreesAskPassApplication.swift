import AppKit
import CoreGitCredential
import Darwin
import Foundation

@MainActor
final class TreesAskPassApplication {
	private let credentialStore = GitCredentialStore()
	private let decisionStore = GitCredentialSaveDecisionStore()
	private var parentMonitor: DispatchSourceTimer?

	func run(arguments: [String], environment: [String: String]) -> Int32 {
		do {
			if arguments.first == "credential" {
				try runCredentialHelper(
					operation: arguments.dropFirst().first ?? "", environment: environment)
				return EXIT_SUCCESS
			}
			let prompt = arguments.first ?? "Authentication required"
			let value = try runAskPass(prompt: prompt, environment: environment)
			FileHandle.standardOutput.write(Data((value + "\n").utf8))
			return EXIT_SUCCESS
		} catch is CancellationError {
			FileHandle.standardError.write(Data("TREES_ASKPASS_CANCELLED\n".utf8))
			return EXIT_FAILURE
		} catch {
			FileHandle.standardError.write(Data("Trees authentication helper failed.\n".utf8))
			return EXIT_FAILURE
		}
	}

	private func runAskPass(prompt: String, environment: [String: String]) throws -> String {
		let kind = AskPassPromptKind(prompt: prompt)
		if kind == .secret, isSSHPassphrase(prompt),
			let descriptor = sshDescriptor(prompt: prompt),
			let secret = try credentialStore.secret(for: descriptor)
		{
			return secret
		}
		let result = try presentPrompt(prompt, kind: kind, environment: environment)
		guard let operationID = environment["TREES_OPERATION_IDENTIFIER"] else {
			return result.value
		}
		decisionStore.setShouldSave(result.shouldSave, operationID: operationID)
		if kind == .secret, isSSHPassphrase(prompt), result.shouldSave,
			let descriptor = sshDescriptor(prompt: prompt)
		{
			try credentialStore.savePending(
				secret: result.value,
				for: descriptor,
				operationID: operationID
			)
		}
		return result.value
	}

	private func presentPrompt(
		_ prompt: String,
		kind: AskPassPromptKind,
		environment: [String: String]
	) throws -> AskPassPromptResult {
		NSApplication.shared.setActivationPolicy(.accessory)
		NSApplication.shared.activate(ignoringOtherApps: true)
		let alert = NSAlert()
		alert.messageText = kind == .hostTrust ? "Trust SSH Host?" : "Git Authentication"
		alert.informativeText = prompt

		if kind == .hostTrust {
			alert.addButton(withTitle: "Trust Once")
			alert.addButton(withTitle: "Cancel")
			startParentMonitor(environment: environment)
			defer { stopParentMonitor() }
			guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
			return AskPassPromptResult(value: "yes", shouldSave: false)
		}

		let input: NSTextField = kind == .secret ? NSSecureTextField() : NSTextField()
		input.placeholderString = kind == .secret ? "Password, token, or passphrase" : "Username"
		input.frame = NSRect(x: 0, y: kind == .secret ? 28 : 0, width: 360, height: 24)
		let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: kind == .secret ? 56 : 24))
		accessory.addSubview(input)
		let saveButton = NSButton(checkboxWithTitle: "Save to Keychain", target: nil, action: nil)
		saveButton.state = .on
		if kind == .secret {
			saveButton.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
			accessory.addSubview(saveButton)
		}
		alert.accessoryView = accessory
		alert.addButton(withTitle: "Continue")
		alert.addButton(withTitle: "Cancel")
		startParentMonitor(environment: environment)
		defer { stopParentMonitor() }
		guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
		return AskPassPromptResult(
			value: input.stringValue,
			shouldSave: kind == .secret && saveButton.state == .on
		)
	}

	private func runCredentialHelper(operation: String, environment: [String: String]) throws {
		let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
		let fields = credentialFields(input)
		guard fields["protocol"] == "https" || fields["protocol"] == "http",
			let host = fields["host"]
		else { return }
		let operationID = environment["TREES_OPERATION_IDENTIFIER"] ?? ""

		switch operation {
		case "get":
			let descriptors = try credentialStore.descriptors().filter {
				$0.kind == .https && $0.host == host
			}
			let descriptor =
				fields["username"].map {
					GitCredentialDescriptor(kind: .https, host: host, account: $0)
				} ?? descriptors.first
			guard let descriptor, let secret = try credentialStore.secret(for: descriptor) else { return }
			writeCredential(fields: ["username": descriptor.account, "password": secret])
		case "store":
			guard let username = fields["username"], let password = fields["password"],
				decisionStore.consumeShouldSave(operationID: operationID)
			else { return }
			try credentialStore.save(
				secret: password,
				for: GitCredentialDescriptor(kind: .https, host: host, account: username)
			)
		case "erase":
			for descriptor in try credentialStore.descriptors()
			where descriptor.kind == .https
				&& descriptor.host == host
				&& (fields["username"] == nil || descriptor.account == fields["username"])
			{
				try credentialStore.delete(descriptor)
			}
		default:
			return
		}
	}

	private func credentialFields(_ input: String) -> [String: String] {
		Dictionary(
			uniqueKeysWithValues: input.split(whereSeparator: \.isNewline).compactMap { line in
				guard let separator = line.firstIndex(of: "=") else { return nil }
				return (String(line[..<separator]), String(line[line.index(after: separator)...]))
			}
		)
	}

	private func writeCredential(fields: [String: String]) {
		let output =
			fields.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: "\n") + "\n\n"
		FileHandle.standardOutput.write(Data(output.utf8))
	}

	private func isSSHPassphrase(_ prompt: String) -> Bool {
		prompt.localizedCaseInsensitiveContains("passphrase")
	}

	private func sshDescriptor(prompt: String) -> GitCredentialDescriptor? {
		guard let firstQuote = prompt.firstIndex(of: "'"),
			let secondQuote = prompt[prompt.index(after: firstQuote)...].firstIndex(of: "'")
		else { return nil }
		let path = String(prompt[prompt.index(after: firstQuote)..<secondQuote])
		return GitCredentialDescriptor(
			kind: .ssh,
			host: "SSH Key",
			account: URL(fileURLWithPath: path).lastPathComponent
		)
	}

	private func startParentMonitor(environment: [String: String]) {
		guard let value = environment["TREES_PARENT_PROCESS_IDENTIFIER"], let parentID = Int32(value)
		else { return }
		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
		timer.setEventHandler {
			if kill(parentID, 0) != 0 {
				NSApplication.shared.abortModal()
			}
		}
		timer.resume()
		parentMonitor = timer
	}

	private func stopParentMonitor() {
		parentMonitor?.cancel()
		parentMonitor = nil
	}
}
