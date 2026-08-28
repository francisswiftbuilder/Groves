import SwiftUI

struct RepositoryWelcomeView: View {
	@ObservedObject var viewModel: RepositoryWindowViewModel
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: () -> Void
	let onCancel: () -> Void
	@FocusState private var isRemoteURLFocused: Bool

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				VStack(spacing: 10) {
					Image(systemName: "point.3.connected.trianglepath.dotted")
						.font(.title2.weight(.medium))
						.symbolRenderingMode(.hierarchical)
						.foregroundStyle(.secondary)
						.accessibilityHidden(true)

					Text("Open a Repository")
						.font(.title2.weight(.semibold))

					Text("Open a repository on this Mac or clone one from a remote URL.")
						.font(.callout)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)

					if isWorking {
						HStack(spacing: 8) {
							ProgressView("Working…")
								.controlSize(.small)
								.font(.caption)
								.foregroundStyle(.secondary)

							Button("Cancel", systemImage: "xmark.circle") {
								onCancel()
							}
							.controlSize(.small)
						}
					}
				}

				ViewThatFits(in: .horizontal) {
					HStack(alignment: .top, spacing: 12) {
						openRepositoryCard
						cloneRepositoryCard
					}

					VStack(spacing: 12) {
						openRepositoryCard
						cloneRepositoryCard
					}
				}
			}
			.frame(maxWidth: 640)
			.padding(.horizontal, 28)
			.padding(.vertical, 32)
			.containerRelativeFrame(.vertical, alignment: .center)
		}
		.scrollBounceBehavior(.basedOnSize)
	}

	private var openRepositoryCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			optionHeader(
				title: "Local Repository",
				description: "Choose an existing Git repository from Finder.",
				systemImage: "folder"
			)

			Button("Choose Repository…", systemImage: "folder.badge.plus") {
				onOpenRepository()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
			.keyboardShortcut("o", modifiers: .command)
			.disabled(isWorking)
		}
		.welcomeCard()
	}

	private var cloneRepositoryCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			optionHeader(
				title: "Clone Repository",
				description: "Download a remote Git repository to this Mac.",
				systemImage: "arrow.triangle.branch"
			)

			TextField(
				"https://github.com/owner/repository.git",
				text: $viewModel.cloneRemoteURL
			)
			.textFieldStyle(.roundedBorder)
			.focused($isRemoteURLFocused)
			.onSubmit(cloneRepository)
			.disabled(isWorking)
			.accessibilityLabel("Remote repository URL")

			Button("Choose Location and Clone…", systemImage: "square.and.arrow.down") {
				cloneRepository()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.regular)
			.disabled(isCloneDisabled)
		}
		.welcomeCard()
	}

	private func optionHeader(
		title: String,
		description: String,
		systemImage: String
	) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: systemImage)
				.font(.body.weight(.medium))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.frame(width: 22, height: 22)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.headline)

				Text(description)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Spacer(minLength: 0)
		}
	}

	private var isCloneDisabled: Bool {
		isWorking || viewModel.trimmedCloneRemoteURL.isEmpty
	}

	private func cloneRepository() {
		guard isCloneDisabled == false else { return }
		onCloneRepository()
	}
}
