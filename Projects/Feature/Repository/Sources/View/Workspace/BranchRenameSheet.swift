import SwiftUI

struct BranchRenameSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var name: String
	let onRename: () -> Void

	var body: some View {
		Form {
			TextField("Branch Name", text: $name)
		}
		.padding(20)
		.frame(width: 380, height: 130)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Rename") { onRename() }
					.buttonStyle(.borderedProminent)
					.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
	}
}
