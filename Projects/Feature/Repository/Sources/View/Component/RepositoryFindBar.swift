import SwiftUI

struct RepositoryFindBar: View {
	@ObservedObject var model: RepositorySearchViewModel
	let prompt: String
	@FocusState private var isFocused: Bool

	var body: some View {
		HStack(spacing: 8) {
			TextField(prompt, text: $model.query)
				.textFieldStyle(.roundedBorder)
				.frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
				.focused($isFocused)
				.onSubmit { model.next() }

			Text(model.statusText)
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(minWidth: 58, alignment: .trailing)

			Button("Previous Match", systemImage: "chevron.up") {
				model.previous()
			}
			.labelStyle(.iconOnly)
			.disabled(model.matches.isEmpty)

			Button("Next Match", systemImage: "chevron.down") {
				model.next()
			}
			.labelStyle(.iconOnly)
			.disabled(model.matches.isEmpty)

			Button("Close Find", systemImage: "xmark") {
				model.isPresented = false
			}
			.labelStyle(.iconOnly)
		}
		.controlSize(.small)
		.padding(.horizontal, 10)
		.frame(minHeight: 36)
		.frame(maxWidth: .infinity, alignment: .trailing)
		.background(.bar)
		.onAppear {
			isFocused = true
		}
	}
}
