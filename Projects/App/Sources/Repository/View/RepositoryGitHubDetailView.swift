import CoreGitCredential
import SwiftUI

struct RepositoryGitHubDetailView: View {
	private struct Request: Hashable {
		let repository: GitHubRepository
		let account: GitCredentialDescriptor
		let accessRevision: Int
	}

	let repository: GitHubRepository?
	let account: GitCredentialDescriptor?
	let accountViewModel: GitAccountViewModel

	@State private var files: (Request, Result<[GitHubRepositoryFile], any Error>)?
	@State private var readme: (Request, Result<Readme, any Error>)?
	@State private var showsAllFiles = false
	@State private var filesRetry = 0
	@State private var readmeRetry = 0

	private struct Readme {
		let blocks: [RepositoryReadmeView.Block]
		let isTruncated: Bool
	}

	private let visibleFileLimit = 6

	private var request: Request? {
		guard let repository, let account else { return nil }
		return Request(
			repository: repository, account: account,
			accessRevision: accountViewModel.repositoryAccessRevision)
	}

	var body: some View {
		let request = request
		Group {
			if let request {
				ScrollView {
					VStack(alignment: .leading, spacing: 20) {
						repositorySummary(request.repository)
						VStack(alignment: .leading) {
							filesContent(for: request)
						}
						.task(id: filesRetry) { await loadFiles(for: request) }
						Divider()
						VStack(alignment: .leading) {
							readmeContent(for: request)
						}
						.task(id: readmeRetry) { await loadReadme(for: request) }
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
				}
				.id(request)
			} else {
				ContentUnavailableView(
					"Select a Repository", systemImage: "doc.text",
					description: Text("View its files and README."))
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background { Color(nsColor: .textBackgroundColor) }
	}

	private func repositorySummary(_ repository: GitHubRepository) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(repository.fullName).font(.title3.weight(.semibold)).lineLimit(2)
				.accessibilityAddTraits(.isHeader)
			if let branch = repository.defaultBranch, !branch.isEmpty {
				Label(branch, systemImage: "arrow.triangle.branch")
					.font(.caption).foregroundStyle(.secondary)
					.lineLimit(1)
			}
			if let description = repository.description, !description.isEmpty {
				Text(description).foregroundStyle(.secondary)
			}
		}
		.textSelection(.enabled)
	}

	@ViewBuilder
	private func filesContent(for request: Request) -> some View {
		if let (loadedRequest, result) = files, loadedRequest == request {
			switch result {
			case .success(let files): filesSection(files)
			case .failure(let error):
				failedSection("Files", error: error) { filesRetry += 1 }
			}
		} else {
			ProgressView("Loading Files…").controlSize(.small)
		}
	}

	@ViewBuilder
	private func readmeContent(for request: Request) -> some View {
		if let (loadedRequest, result) = readme, loadedRequest == request {
			switch result {
			case .success(let readme): readmeSection(readme, repository: request.repository)
			case .failure(let error):
				failedSection("README", error: error) { readmeRetry += 1 }
			}
		} else {
			ProgressView("Loading README…").controlSize(.small)
		}
	}

	private func failedSection(
		_ title: LocalizedStringKey, error: any Error, retry: @escaping () -> Void
	) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(.headline)
			Text(error.localizedDescription).foregroundStyle(.secondary)
			Button("Try Again", action: retry).buttonStyle(.link)
		}
	}

	private func filesSection(_ files: [GitHubRepositoryFile]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Files").font(.headline)
			if files.isEmpty {
				Text("No files available").foregroundStyle(.secondary)
			}
			ForEach(files.prefix(showsAllFiles ? files.count : visibleFileLimit)) { file in
				if let url = file.webURL {
					Link(destination: url) { fileLabel(file) }
				} else {
					fileLabel(file)
				}
			}
			if files.count > visibleFileLimit {
				Button(showsAllFiles ? "Show Fewer Files" : "Show All \(files.count) Files") {
					showsAllFiles.toggle()
				}
				.buttonStyle(.link)
			}
		}
	}

	private func fileLabel(_ file: GitHubRepositoryFile) -> some View {
		Label(file.name, systemImage: file.isDirectory ? "folder" : "doc")
			.lineLimit(1)
			.truncationMode(.middle)
	}

	private func readmeSection(_ readme: Readme, repository: GitHubRepository) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("README").font(.headline)
			if !readme.blocks.isEmpty {
				RepositoryReadmeView(blocks: readme.blocks)
				if readme.isTruncated {
					Link("Read the Full README on GitHub", destination: repository.webURL)
				}
			} else {
				Text("No README available").foregroundStyle(.secondary)
			}
		}
	}

	private func loadFiles(for request: Request) async {
		if files?.0 != request { showsAllFiles = false }
		files = nil
		do {
			let result = try await accountViewModel.loadRepositoryFiles(
				for: request.repository, account: request.account)
			try Task.checkCancellation()
			files = (request, .success(result))
		} catch is CancellationError {
			return
		} catch {
			guard !Task.isCancelled else { return }
			files = (request, .failure(error))
		}
	}

	private func loadReadme(for request: Request) async {
		readme = nil
		let repository = request.repository
		do {
			let result = try await accountViewModel.loadRepositoryReadme(
				for: repository, account: request.account)
			let blocks: [RepositoryReadmeView.Block]
			if let markdown = result.markdown, !markdown.isEmpty {
				let baseURL = repository.webURL
					.appending(
						path: "blob/\(repository.defaultBranch ?? "HEAD")", directoryHint: .isDirectory)
				blocks = try await RepositoryReadmeView.prepare(markdown: markdown, baseURL: baseURL)
			} else {
				blocks = []
			}
			try Task.checkCancellation()
			readme = (request, .success(Readme(blocks: blocks, isTruncated: result.isTruncated)))
		} catch is CancellationError {
			return
		} catch {
			guard !Task.isCancelled else { return }
			readme = (request, .failure(error))
		}
	}
}
