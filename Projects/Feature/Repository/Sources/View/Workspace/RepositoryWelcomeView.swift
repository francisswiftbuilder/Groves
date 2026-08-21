import SwiftUI

struct RepositoryWelcomeContainerView: View {
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: (String) -> Void

	var body: some View {
		NavigationSplitView {
			List {}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			RepositoryWelcomeView(
				isWorking: isWorking,
				onOpenRepository: onOpenRepository,
				onCloneRepository: onCloneRepository
			)
		}
	}
}

struct RepositoryWelcomeView: View {
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: (String) -> Void
	@State private var remoteURL = ""
	@FocusState private var isRemoteURLFocused: Bool

	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				VStack(spacing: 12) {
					Image(systemName: "point.3.connected.trianglepath.dotted")
						.font(.system(size: 25, weight: .medium))
						.symbolRenderingMode(.hierarchical)
						.foregroundStyle(.primary)
						.frame(width: 52, height: 52)
						.background(.quaternary, in: .circle)
						.accessibilityHidden(true)

					Text("Open a Repository")
						.font(.title.weight(.semibold))

					Text("Open a repository on this Mac or clone one from a remote URL.")
						.font(.callout)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)

					if isWorking {
						ProgressView("Working…")
							.controlSize(.small)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

				ViewThatFits(in: .horizontal) {
					HStack(alignment: .top, spacing: 14) {
						openRepositoryCard
						cloneRepositoryCard
					}

					VStack(spacing: 14) {
						openRepositoryCard
						cloneRepositoryCard
					}
				}
			}
			.frame(maxWidth: 680)
			.padding(.horizontal, 32)
			.padding(.vertical, 40)
			.containerRelativeFrame(.vertical, alignment: .center)
		}
		.scrollBounceBehavior(.basedOnSize)
	}

	private var openRepositoryCard: some View {
		VStack(alignment: .leading, spacing: 14) {
			optionHeader(
				title: "Local Repository",
				description: "Choose an existing Git repository from Finder.",
				systemImage: "folder"
			)

			Spacer(minLength: 10)

			Button("Choose Repository…", systemImage: "folder.badge.plus") {
				onOpenRepository()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.keyboardShortcut("o", modifiers: .command)
			.disabled(isWorking)
		}
		.welcomeCard()
	}

	private var cloneRepositoryCard: some View {
		VStack(alignment: .leading, spacing: 14) {
			optionHeader(
				title: "Clone Repository",
				description: "Download a remote Git repository to this Mac.",
				systemImage: "arrow.triangle.branch"
			)

			TextField("https://github.com/owner/repository.git", text: $remoteURL)
				.textFieldStyle(.roundedBorder)
				.focused($isRemoteURLFocused)
				.onSubmit(cloneRepository)
				.disabled(isWorking)
				.accessibilityLabel("Remote repository URL")

			Button("Choose Location and Clone…", systemImage: "square.and.arrow.down") {
				cloneRepository()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.disabled(isCloneDisabled)
		}
		.welcomeCard()
	}

	private func optionHeader(
		title: String,
		description: String,
		systemImage: String
	) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: systemImage)
				.font(.system(size: 16, weight: .medium))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 32, height: 32)
				.background(.quaternary, in: .rect(cornerRadius: 8))
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

	private var trimmedRemoteURL: String {
		remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var isCloneDisabled: Bool {
		isWorking || trimmedRemoteURL.isEmpty
	}

	private func cloneRepository() {
		guard isCloneDisabled == false else { return }
		onCloneRepository(trimmedRemoteURL)
	}
}

extension View {
	fileprivate func welcomeCard() -> some View {
		padding(18)
			.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
			.background(.regularMaterial, in: .rect(cornerRadius: 14))
			.overlay {
				RoundedRectangle(cornerRadius: 14)
					.stroke(.quaternary, lineWidth: 1)
			}
	}
}
