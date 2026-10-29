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
			TextField("Branch Name", text: $name)
				.disabled(isLoading)
			if let errorMessage {
				Label(errorMessage, systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.padding(20)
		.frame(width: 380, height: 220)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.disabled(isLoading)
				Button("Rename") { onRename() }
					.buttonStyle(.borderedProminent)
					.disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
		.interactiveDismissDisabled(isLoading)
	}
}
