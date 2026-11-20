import AppKit
import DomainGitInterface
import SwiftUI

struct NewBranchSheet: View {
	@Binding var name: String
	@Binding var checkout: Bool
	let startCommit: GitCommit?
	let remoteStart: String?
	let isLoading: Bool
	let errorMessage: String?
	let errorDetails: String?
	let onCancel: () -> Void
	let onCreate: () -> Void

	init(
		name: Binding<String>,
		checkout: Binding<Bool> = .constant(true),
		startCommit: GitCommit? = nil,
		remoteStart: String? = nil,
		isLoading: Bool = false,
		errorMessage: String? = nil,
		errorDetails: String? = nil,
		onCancel: @escaping () -> Void,
		onCreate: @escaping () -> Void
	) {
		_name = name
		_checkout = checkout
		self.startCommit = startCommit
		self.remoteStart = remoteStart
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.errorDetails = errorDetails
		self.onCancel = onCancel
		self.onCreate = onCreate
	}

	var body: some View {
		Form {
			Section {
				TextField("Branch name", text: $name)
					.textFieldStyle(.roundedBorder)
					.disabled(isLoading)
				Toggle("Check Out New Branch", isOn: $checkout)
					.disabled(isLoading)
				if let errorMessage {
					Label(errorMessage, systemImage: "exclamationmark.triangle")
						.font(.caption)
						.foregroundStyle(.red)
						.contextMenu {
							if let errorDetails {
								Button("Copy Git Details") {
									NSPasteboard.general.clearContents()
									NSPasteboard.general.setString(errorDetails, forType: .string)
								}
							}
						}
				}
			} footer: {
				Text(
					"Starts at \(remoteStart ?? startCommit?.shortHash ?? "HEAD")."
				)
				.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text("New Branch")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel, action: onCancel)
					.keyboardShortcut(.cancelAction)
					.disabled(isLoading)
				Button("Create", action: onCreate)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(20)
		}
		.frame(width: 440, height: 280)
		.interactiveDismissDisabled(isLoading)
	}
}
