import SwiftUI

struct BranchRenameSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var name: String
	let isLoading: Bool
	let errorMessage: String?
	let onRename: () -> Void

	init(
		name: Binding<String>, isLoading: Bool = false, errorMessage: String? = nil,
		onRename: @escaping () -> Void
	) {
		_name = name
		self.isLoading = isLoading
		self.errorMessage = errorMessage
		self.onRename = onRename
	}

	var body: some View {
		Form {
			TextField("Name", text: $name)
				.disabled(isLoading)
			if let errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text("Rename Branch")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
					.disabled(isLoading)
				Button("Rename") { onRename() }
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(20)
		}
		.frame(width: 440, height: 220)
		.interactiveDismissDisabled(isLoading)
	}
}
