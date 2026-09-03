import AppKit
import CoreGitCredential
import SwiftUI
import UniformTypeIdentifiers

struct GrovesSettingsView: View {
	@AppStorage("externalEditorBundleIdentifier") private var bundleIdentifier = ""
	@AppStorage("externalEditorDisplayName") private var displayName = "System Default"
	@State private var selectionError: String?
	@State private var credentials: [GitCredentialDescriptor] = []
	@State private var credentialError: String?
	private let credentialStore = GitCredentialStore()

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
			Section("Credentials") {
				if credentials.isEmpty {
					ContentUnavailableView(
						"No Saved Credentials",
						systemImage: "key",
						description: Text("Saved Git accounts and SSH key passphrases appear here.")
					)
				} else {
					ForEach(credentials) { credential in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(credential.account)
								Text(credential.host)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							Text(credential.kind == .https ? "HTTPS" : "SSH")
								.font(.caption)
								.foregroundStyle(.secondary)
							Button("Delete", role: .destructive) {
								deleteCredential(credential)
							}
						}
					}
					Button("Delete All", role: .destructive) { deleteAllCredentials() }
				}
				if let credentialError {
					Label(credentialError, systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
		}
		.formStyle(.grouped)
		.padding(20)
		.frame(width: 520, height: 520)
		.navigationTitle("Groves Settings")
		.onChange(of: bundleIdentifier, initial: true) { validateSelection() }
		.task { loadCredentials() }
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

	private func loadCredentials() {
		do {
			credentials = try credentialStore.descriptors()
			credentialError = nil
		} catch {
			credentialError = error.localizedDescription
		}
	}

	private func deleteCredential(_ credential: GitCredentialDescriptor) {
		do {
			try credentialStore.delete(credential)
			loadCredentials()
		} catch {
			credentialError = error.localizedDescription
		}
	}

	private func deleteAllCredentials() {
		do {
			try credentialStore.deleteAll()
			loadCredentials()
		} catch {
			credentialError = error.localizedDescription
		}
	}
}

#Preview {
	GrovesSettingsView()
}
