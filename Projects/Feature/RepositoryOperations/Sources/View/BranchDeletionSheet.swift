import SwiftUI

struct BranchDeletionSheet: View {
	let title: String
	let message: String
	let optionTitle: String
	let unavailableReason: String?
	let onCancel: () -> Void
	let onDelete: (Bool) -> Void
	@State private var deleteLinkedBranch = false

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(message)
				.fixedSize(horizontal: false, vertical: true)
			Toggle(isOn: $deleteLinkedBranch) {
				Text(optionTitle).fixedSize(horizontal: false, vertical: true)
			}
			.toggleStyle(.checkbox)
			.disabled(unavailableReason != nil)
			if let unavailableReason {
				Text(unavailableReason)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(20)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text(title)
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
				Button("Delete", role: .destructive) {
					onDelete(deleteLinkedBranch && unavailableReason == nil)
				}
			}
			.padding(20)
		}
		.frame(width: 460)
	}
}
