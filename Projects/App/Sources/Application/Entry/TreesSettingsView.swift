import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TreesSettingsView: View {
	@AppStorage("externalEditorBundleIdentifier") private var bundleIdentifier = ""
	@AppStorage("externalEditorDisplayName") private var displayName = "System Default"
	@State private var selectionError: String?

	var body: some View {
		Form {
			Section("General") {
				Picker("Open conflict files with", selection: $bundleIdentifier) {
					Text("System Default").tag("")
					if !bundleIdentifier.isEmpty {
						Text(displayName).tag(bundleIdentifier)
					}
				}
				LabeledContent("Selected Application") {
					HStack(spacing: 8) {
						Image(nsImage: selectedApplicationIcon)
							.resizable()
							.frame(width: 24, height: 24)
						Text(selectedApplicationName)
					}
				}
				Button("Choose Application…") { chooseApplication() }
				if let selectionError {
					Label(selectionError, systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
		}
		.formStyle(.grouped)
		.padding(20)
		.frame(width: 480, height: 260)
		.navigationTitle("Trees Settings")
		.onChange(of: bundleIdentifier, initial: true) { validateSelection() }
	}

	private var selectedApplicationURL: URL? {
		guard !bundleIdentifier.isEmpty else { return nil }
		return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
	}

	private var selectedApplicationName: String {
		bundleIdentifier.isEmpty ? "System Default" : displayName
	}

	private var selectedApplicationIcon: NSImage {
		guard let selectedApplicationURL else {
			return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
		}
		return NSWorkspace.shared.icon(forFile: selectedApplicationURL.path)
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

#Preview {
	TreesSettingsView()
}
