import SwiftUI

struct NewBranchSheet: View {
	@Binding var name: String
	let onCancel: () -> Void
	let onCreate: () -> Void

	init(
		name: Binding<String>,
		onCancel: @escaping () -> Void,
		onCreate: @escaping () -> Void
	) {
		_name = name
		self.onCancel = onCancel
		self.onCreate = onCreate
	}

	var body: some View {
		Form {
			Section {
				TextField("Branch name", text: $name)
					.textFieldStyle(.roundedBorder)
			} header: {
				Text("Create Branch")
			} footer: {
				Text("The new branch starts at the current HEAD and becomes the active branch.")
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.frame(width: 420, height: 180)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel, action: onCancel)
				Button("Create", action: onCreate)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			.padding(12)
			.background(.bar)
		}
	}
}
