import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
	@AppStorage(ExternalEditorPreferenceKey.bundleIdentifier) private var bundleIdentifier = ""
	@AppStorage("externalEditorDisplayName") private var displayName = "System Default"
	@State private var selectionError: String?
	private let accountViewModel: GitAccountViewModel

	init(accountViewModel: GitAccountViewModel) {
		self.accountViewModel = accountViewModel
	}

	var body: some View {
		Form {
			Section("Editing") {
				HStack {
					Picker("Conflict editor", selection: $bundleIdentifier) {
						Text("System Default").tag("")
						if !bundleIdentifier.isEmpty {
							Text(displayName).tag(bundleIdentifier)
						}
					}
					Button("Choose…") { chooseApplication() }
				}
				if let selectionError {
					Label(selectionError, systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
			GitIdentitySection(viewModel: accountViewModel, showsSaveActions: true)
			if let message = accountViewModel.identityErrorMessage {
				Section {
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
		}
		.formStyle(.grouped)
		.onChange(of: bundleIdentifier, initial: true) { validateSelection() }
	}

	private var selectedApplicationURL: URL? {
		guard !bundleIdentifier.isEmpty else { return nil }
		return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
	}

	private func chooseApplication() {
		let panel = NSOpenPanel()
		panel.title = "Choose an Editor"
		panel.prompt = "Choose"
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [.application]
		guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
		guard let bundle = Bundle(url: applicationURL), let identifier = bundle.bundleIdentifier else {
			selectionError = "The selected application does not have a valid bundle identifier."
			return
		}
		bundleIdentifier = identifier
		displayName = FileManager.default.displayName(atPath: applicationURL.path)
		selectionError = nil
	}

	private func validateSelection() {
		guard !bundleIdentifier.isEmpty else {
			displayName = "System Default"
			selectionError = nil
			return
		}
		selectionError =
			selectedApplicationURL == nil
			? "The selected application is no longer installed. Choose another application."
			: nil
	}

}
