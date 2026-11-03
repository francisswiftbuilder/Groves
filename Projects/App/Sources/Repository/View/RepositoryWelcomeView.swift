import SwiftUI

struct RepositoryWelcomeView: View {
	@Bindable var viewModel: RepositoryWindowViewModel
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: () -> Void
	let onCancel: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Text("Repositories").font(.title2.weight(.semibold))
			Button("Open Repository…", action: onOpenRepository)
				.keyboardShortcut("o", modifiers: .command)
				.disabled(isWorking)
			Divider()
			VStack(alignment: .leading, spacing: 8) {
				Text("Clone Repository").font(.headline)
				TextField(
					"Repository URL", text: $viewModel.cloneRemoteURL,
					prompt: Text("https://github.com/owner/repository.git")
				)
				.textFieldStyle(.roundedBorder)
				.autocorrectionDisabled()
				.onSubmit(cloneRepository)
				.disabled(isWorking)
				Button("Clone…", action: cloneRepository)
					.disabled(isCloneDisabled)
			}
			if isWorking {
				HStack {
					ProgressView("Working…").controlSize(.small)
					Spacer()
					Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
				}
			}
		}
		.frame(maxWidth: 400)
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var isCloneDisabled: Bool {
		isWorking || viewModel.trimmedCloneRemoteURL.isEmpty
	}

	private func cloneRepository() {
		guard isCloneDisabled == false else { return }
		onCloneRepository()
	}
}
