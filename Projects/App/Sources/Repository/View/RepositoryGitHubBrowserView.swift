import CoreGitCredential
import SwiftUI

struct RepositoryGitHubBrowserView: View {
	let accountViewModel: GitAccountViewModel
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onClone: (String) -> Void
	let onCancel: () -> Void

	@State private var query = ""
	@State private var selection: GitHubRepository.ID?

	private var repositories: [GitHubRepository] {
		accountViewModel.accessibleRepositories ?? []
	}

	private var filteredRepositories: [GitHubRepository] {
		let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !search.isEmpty else { return repositories }
		return repositories.filter {
			$0.fullName.localizedStandardContains(search)
				|| $0.description?.localizedStandardContains(search) == true
		}
	}

	private var selectedRepository: GitHubRepository? {
		repositories.first { $0.id == selection }
	}

	private var enteredRemoteURL: String? {
		RepositoryWindowViewModel.cloneRemoteURL(from: query)
	}

	private var cloneTarget: String? {
		enteredRemoteURL ?? filteredRepositories.first { $0.id == selection }?.cloneURL.absoluteString
	}

	var body: some View {
		GeometryReader { geometry in
			VStack(spacing: 0) {
				Divider()
				HSplitView {
					repositoryList
						.frame(
							minWidth: min(195, geometry.size.width * 0.4), idealWidth: 255,
							maxWidth: 360, maxHeight: .infinity)
					RepositoryGitHubDetailView(
						repository: selectedRepository, account: accountViewModel.account,
						accountViewModel: accountViewModel
					)
					.frame(
						minWidth: min(270, geometry.size.width * 0.55),
						maxWidth: .infinity, maxHeight: .infinity)
				}
				Divider()
			}
			.safeAreaInset(edge: .top, spacing: 0) {
				header
			}
			.safeAreaInset(edge: .bottom, spacing: 0) {
				footer
			}
		}
		.onChange(of: accountViewModel.repositoryAccessRevision) { selection = nil }
		.task(id: accountViewModel.repositoryAccessRevision) {
			await loadRepositories()
		}
	}

	private var header: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text(accountViewModel.account == nil ? "Clone Repository" : "GitHub").font(.headline)
					if let account = accountViewModel.account {
						Text(verbatim: "@\(account.account)")
							.font(.caption).foregroundStyle(.secondary)
					}
				}
				Spacer()
				TextField("Search or enter repository URL", text: $query)
					.textFieldStyle(.roundedBorder)
					.autocorrectionDisabled()
					.frame(maxWidth: 290)
					.onSubmit(cloneSelection)
					.disabled(isWorking)
				Button {
					Task { await loadRepositories(forceRefresh: true) }
				} label: {
					Label(
						"Refresh Repositories",
						systemImage: accountViewModel.repositoryLoadError == nil
							? "arrow.clockwise" : "exclamationmark.circle")
				}
				.labelStyle(.iconOnly)
				.help(accountViewModel.repositoryLoadError ?? "Refresh Repositories")
				.disabled(accountViewModel.account == nil || accountViewModel.isLoadingRepositories)
			}
			.padding(12)
		}
		.background(.bar)
	}

	@ViewBuilder
	private var repositoryList: some View {
		if let enteredRemoteURL {
			ContentUnavailableView {
				Label("Clone from URL", systemImage: "link")
			} description: {
				Text(enteredRemoteURL).lineLimit(2).truncationMode(.middle)
			}
		} else if query.contains("://") || query.hasPrefix("git@") {
			ContentUnavailableView(
				"Check Repository URL", systemImage: "link",
				description: Text("Enter a complete HTTPS clone URL."))
		} else if accountViewModel.account == nil {
			ContentUnavailableView {
				Label("Clone a Repository", systemImage: "arrow.down.to.line")
			} description: {
				Text(
					"Paste a repository URL above or connect a GitHub account to browse your repositories.")
			} actions: {
				SettingsLink { Text("Open Settings…") }
			}
		} else if repositories.isEmpty && accountViewModel.isLoadingRepositories {
			ProgressView("Loading Repositories…")
		} else if repositories.isEmpty, let errorMessage = accountViewModel.repositoryLoadError {
			ContentUnavailableView {
				Label("Couldn’t Load Repositories", systemImage: "exclamationmark.triangle")
			} description: {
				Text(errorMessage)
			} actions: {
				Button("Try Again") { Task { await loadRepositories(forceRefresh: true) } }
			}
		} else if accountViewModel.accessibleRepositories == nil {
			ProgressView("Loading Repositories…")
		} else if repositories.isEmpty {
			ContentUnavailableView(
				"No Accessible Repositories", systemImage: "folder",
				description: Text("Check which repositories your GitHub token can access."))
		} else if filteredRepositories.isEmpty && accountViewModel.isLoadingRepositories {
			ProgressView("Searching Repositories…")
		} else if filteredRepositories.isEmpty {
			ContentUnavailableView.search(text: query)
		} else {
			repositoryRows
		}
	}

	private var repositoryRows: some View {
		List(filteredRepositories, selection: $selection) { repository in
			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					Text(repository.fullName).font(.headline)
					if repository.isPrivate {
						Image(systemName: "lock").accessibilityLabel("Private repository")
					}
					if repository.isArchived {
						Image(systemName: "archivebox").accessibilityLabel("Archived repository")
					}
				}
				if let description = repository.description, !description.isEmpty {
					Text(description)
						.font(.caption).foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
			.padding(.vertical, 4)
			.tag(repository.id)
		}
		.listStyle(.inset)
		.contextMenu(forSelectionType: GitHubRepository.ID.self) { ids in
			if let id = ids.first, ids.count == 1,
				let repository = filteredRepositories.first(where: { $0.id == id })
			{
				Link("View on GitHub", destination: repository.webURL)
				Button("Clone…") { cloneRepository(id) }.disabled(isWorking)
			}
		} primaryAction: { ids in
			if let id = ids.first, ids.count == 1 { cloneRepository(id) }
		}
	}

	private var footer: some View {
		VStack(spacing: 0) {
			HStack {
				Button("Open Local…", action: onOpenRepository)
					.keyboardShortcut("o", modifiers: .command)
					.disabled(isWorking)
				Spacer()
				if isWorking {
					ProgressView().controlSize(.small)
					Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
				} else {
					if enteredRemoteURL == nil, let repository = selectedRepository {
						Link("View on GitHub", destination: repository.webURL)
					}
					Button("Clone…", action: cloneSelection)
						.keyboardShortcut(.defaultAction)
						.disabled(cloneTarget == nil)
				}
			}
			.padding(12)
		}
		.background(.bar)
	}

	private func cloneRepository(_ id: GitHubRepository.ID) {
		guard !isWorking, let repository = filteredRepositories.first(where: { $0.id == id })
		else { return }
		onClone(repository.cloneURL.absoluteString)
	}

	private func cloneSelection() {
		guard !isWorking, let cloneTarget else { return }
		onClone(cloneTarget)
	}

	private func loadRepositories(forceRefresh: Bool = false) async {
		guard let account = accountViewModel.account else { return }
		_ = try? await accountViewModel.loadRepositories(for: account, forceRefresh: forceRefresh)
	}
}
