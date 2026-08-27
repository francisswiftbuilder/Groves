import SwiftUI

struct RemoteEditorSheet: View {
	@Environment(\.dismiss) private var dismiss
	let presentation: RemoteEditorPresentation
	let onSave: (String, String, String?) -> Void
	@State private var name: String
	@State private var fetchURL: String
	@State private var pushURL: String

	init(
		presentation: RemoteEditorPresentation,
		onSave: @escaping (String, String, String?) -> Void
	) {
		self.presentation = presentation
		self.onSave = onSave
		switch presentation {
		case .add:
			_name = State(initialValue: "")
			_fetchURL = State(initialValue: "")
			_pushURL = State(initialValue: "")
		case .edit(let remote):
			_name = State(initialValue: remote.name)
			_fetchURL = State(initialValue: remote.fetchURL ?? "")
			_pushURL = State(initialValue: remote.pushURL ?? "")
		}
	}

	var body: some View {
		Form {
			TextField("Name", text: $name).disabled(isEditing)
			TextField("Fetch URL", text: $fetchURL)
			TextField("Push URL", text: $pushURL, prompt: Text("Uses fetch URL when empty"))
			if fetchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				Text("A fetch URL is required.")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
		.formStyle(.grouped)
		.padding(16)
		.frame(width: 500, height: 220)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button(isEditing ? "Save" : "Add Remote") {
					onSave(
						name.trimmingCharacters(in: .whitespacesAndNewlines),
						fetchURL.trimmingCharacters(in: .whitespacesAndNewlines),
						normalizedPushURL
					)
				}
				.buttonStyle(.borderedProminent)
				.disabled(!isValid)
			}
			.padding(12)
			.background(.bar)
		}
	}

	private var isEditing: Bool {
		if case .edit = presentation { return true }
		return false
	}

	private var isValid: Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !fetchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private var normalizedPushURL: String? {
		let value = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
		return value.isEmpty ? nil : value
	}
}

#Preview {
	RemoteEditorSheet(presentation: .add) { _, _, _ in }
}
