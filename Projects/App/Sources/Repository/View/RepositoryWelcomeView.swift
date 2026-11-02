import SwiftUI

struct RepositoryWelcomeView: View {
	@Bindable var viewModel: RepositoryWindowViewModel
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: () -> Void
	let onCancel: () -> Void

	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				VStack(spacing: 10) {
					Image(systemName: "point.3.connected.trianglepath.dotted")
						.font(.largeTitle)
						.symbolRenderingMode(.hierarchical)
						.foregroundStyle(.secondary)
						.accessibilityHidden(true)

					Text("Open a Repository")
						.font(.title.weight(.semibold))

					Text("Choose a repository on this Mac or clone one from a URL.")
						.font(.callout)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}

				Button("Open Repository…", systemImage: "folder") {
					onOpenRepository()
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.keyboardShortcut("o", modifiers: .command)
				.disabled(isWorking)

				Divider()

				VStack(alignment: .leading, spacing: 12) {
					Text("Clone a Repository")
						.font(.headline)

					LabeledContent("Repository URL") {
						TextField(
							"Repository URL", text: $viewModel.cloneRemoteURL,
							prompt: Text("https://github.com/owner/repository.git")
						)
						.labelsHidden()
						.textFieldStyle(.roundedBorder)
						.autocorrectionDisabled()
						.multilineTextAlignment(.leading)
						.onSubmit(cloneRepository)
						.disabled(isWorking)
					}

					Button("Clone Repository…", systemImage: "arrow.down.to.line") {
						cloneRepository()
					}
					.disabled(isCloneDisabled)
					.help("Choose where to save the repository, then clone it.")
				}

				if isWorking {
					HStack(spacing: 12) {
						ProgressView("Working…")
							.controlSize(.small)
						Button("Cancel", action: onCancel)
							.keyboardShortcut(.cancelAction)
					}
				}

				SettingsLink {
					Text("Accounts…")
				}
				.buttonStyle(.link)
				.font(.callout)
			}
			.frame(maxWidth: 460)
			.padding(32)
			.frame(maxWidth: .infinity)
			.containerRelativeFrame(.vertical, alignment: .center)
		}
		.scrollBounceBehavior(.basedOnSize)
	}

	private var isCloneDisabled: Bool {
		isWorking || viewModel.trimmedCloneRemoteURL.isEmpty
	}

	private func cloneRepository() {
		guard isCloneDisabled == false else { return }
		onCloneRepository()
	}
}
