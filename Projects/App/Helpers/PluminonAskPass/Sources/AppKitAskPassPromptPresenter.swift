import AppKit
import CoreGitCredential
import Foundation

@MainActor
final class AppKitAskPassPromptPresenter: GitCredentialPromptPresenting {
	private let parentProcessIdentifier: Int32?
	private let parentMonitor: any AskPassParentMonitoring

	init(
		parentProcessIdentifier: Int32?,
		parentMonitor: any AskPassParentMonitoring = AskPassParentMonitor()
	) {
		self.parentProcessIdentifier = parentProcessIdentifier
		self.parentMonitor = parentMonitor
	}

	func presentPrompt(
		_ prompt: String,
		kind: GitCredentialPromptKind
	) throws -> GitCredentialPromptAnswer {
		NSApplication.shared.setActivationPolicy(.accessory)
		NSApplication.shared.activate(ignoringOtherApps: true)
		let alert = NSAlert()
		alert.messageText = kind == .hostTrust ? "Trust SSH Host?" : "Git Authentication"
		alert.informativeText = prompt

		if kind == .hostTrust {
			alert.addButton(withTitle: "Trust Once")
			alert.addButton(withTitle: "Cancel")
			guard runModal(alert) == .alertFirstButtonReturn else { throw CancellationError() }
			return GitCredentialPromptAnswer(value: "yes", shouldSave: false)
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
		guard runModal(alert) == .alertFirstButtonReturn else { throw CancellationError() }
		return GitCredentialPromptAnswer(
			value: input.stringValue,
			shouldSave: kind == .secret && saveButton.state == .on
		)
	}

	private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
		if let parentProcessIdentifier {
			parentMonitor.startMonitoring(parentProcessIdentifier: parentProcessIdentifier) {
				NSApplication.shared.abortModal()
			}
		}
		defer { parentMonitor.stopMonitoring() }
		return alert.runModal()
	}
}
