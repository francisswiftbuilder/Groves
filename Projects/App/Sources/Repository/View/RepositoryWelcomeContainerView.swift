import DomainGitInterface
import SwiftUI

struct RepositoryWelcomeContainerView: View {
	private enum Source: Hashable {
		case local, remote
	}

	let accountViewModel: GitAccountViewModel
	let repositories: [SavedRepository]
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onOpenSavedRepository: (UUID) -> Void
	let onCloneRepository: (String) -> Void
	let onCancel: () -> Void

	@State private var selection: Source?
	@State private var localSelection: UUID?

	private var source: Source {
		selection ?? .remote
	}

	var body: some View {
		NavigationSplitView {
			List(selection: Binding<Source?>(get: { source }, set: { selection = $0 })) {
				sourceRow(.local, title: "Local Repositories", systemImage: "folder")
				sourceRow(.remote, title: "Remote Repositories", systemImage: "network")
			}
			.listStyle(.sidebar)
			.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			switch source {
			case .local:
				localRepositories
			case .remote:
				RepositoryGitHubBrowserView(
					accountViewModel: accountViewModel, isWorking: isWorking,
					onOpenRepository: onOpenRepository, onClone: onCloneRepository,
					onCancel: onCancel)
			}
		}
	}

	private func sourceRow(_ source: Source, title: LocalizedStringKey, systemImage: String)
		-> some View
	{
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
				.frame(width: 16)
			Text(title)
				.foregroundStyle(.primary)
				.lineLimit(1)
		}
		.contentShape(.rect)
		.tag(source)
	}

	private var localRepositories: some View {
		Group {
			if repositories.isEmpty {
				ContentUnavailableView(
					"No Local Repositories", systemImage: "folder",
					description: Text("Open an existing repository or clone a remote repository."))
			} else {
				List(repositories, selection: $localSelection) { repository in
					VStack(alignment: .leading, spacing: 3) {
						Text(repository.name).font(.headline)
						Text(repository.url.path)
							.font(.caption).foregroundStyle(.secondary)
							.lineLimit(1).truncationMode(.middle)
					}
					.padding(.vertical, 4)
					.tag(repository.id)
				}
				.contextMenu(forSelectionType: UUID.self) { ids in
					if let id = ids.first, ids.count == 1 {
						Button("Open") { openSavedRepository(id) }.disabled(isWorking)
					}
				} primaryAction: { ids in
					if let id = ids.first, ids.count == 1 { openSavedRepository(id) }
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .bottom, spacing: 0) {
			VStack(spacing: 0) {
				Divider()
				HStack {
					Button("Open Local…", action: onOpenRepository)
						.keyboardShortcut("o", modifiers: .command)
						.disabled(isWorking)
					Spacer()
					if isWorking {
						ProgressView().controlSize(.small)
						Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
					} else {
						Button("Open") {
							if let localSelection { openSavedRepository(localSelection) }
						}
						.keyboardShortcut(.defaultAction)
						.disabled(localSelection == nil)
					}
				}
				.padding(12)
			}
			.background(.bar)
		}
	}

	private func openSavedRepository(_ id: UUID) {
		guard !isWorking, repositories.contains(where: { $0.id == id }) else { return }
		onOpenSavedRepository(id)
	}
}
