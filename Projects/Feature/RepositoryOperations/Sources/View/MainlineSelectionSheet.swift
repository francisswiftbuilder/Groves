import SwiftUI

struct MainlineSelectionSheet: View {
	@Environment(\.dismiss) private var dismiss
	let action: PendingMainlineAction
	let onSelect: (Int) -> Void

	init(action: PendingMainlineAction, onSelect: @escaping (Int) -> Void) {
		self.action = action
		self.onSelect = onSelect
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Choose the mainline parent for \(action.commit.shortHash).")
				.foregroundStyle(.secondary)
			ForEach(Array(action.commit.parentHashes.enumerated()), id: \.offset) { index, hash in
				Button {
					onSelect(index + 1)
				} label: {
					HStack {
						Text("Parent \(index + 1)")
						Spacer()
						Text(String(hash.prefix(12)))
							.font(.system(.body, design: .monospaced))
							.foregroundStyle(.secondary)
					}
				}
				.buttonStyle(.bordered)
			}
		}
		.padding(20)
		.safeAreaInset(edge: .top, spacing: 0) {
			Text(action.title)
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 20)
		}
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
			}
			.padding(20)
		}
		.frame(width: 440)
	}
}
