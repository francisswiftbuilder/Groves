import CoreGitCredential
import SwiftUI

struct RepositoryGitHubDetailView: View {
	private struct Request: Equatable {
		let repository: GitHubRepository
		let account: GitCredentialDescriptor
		let accessRevision: Int
		let refreshCount: Int
	}

	let repository: GitHubRepository?
	let account: GitCredentialDescriptor?
	let accountViewModel: GitAccountViewModel

	@State private var completedRequest: Request?
	@State private var preview: GitHubRepositoryPreview?
	@State private var readme: AttributedString?
	@State private var errorMessage: String?
	@State private var showsAllFiles = false
	@State private var refreshCount = 0

	private let visibleFileLimit = 6

	private var request: Request? {
		guard let repository, let account else { return nil }
		return Request(
			repository: repository, account: account,
			accessRevision: accountViewModel.repositoryAccessRevision, refreshCount: refreshCount)
	}

	var body: some View {
		let request = request
		Group {
			if let request {
				ScrollView {
					VStack(alignment: .leading, spacing: 20) {
						repositorySummary(request.repository)
						previewContent(for: request)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
				}
				.id(request.repository.id)
			} else {
				ContentUnavailableView(
					"Select a Repository", systemImage: "doc.text",
					description: Text("View its files and README."))
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background { Color(nsColor: .textBackgroundColor) }
		.task(id: request) {
			if let request {
				await loadPreview(for: request)
			} else {
				completedRequest = nil
				preview = nil
				readme = nil
			}
		}
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
	private func previewContent(for request: Request) -> some View {
		if completedRequest == request, let preview {
			filesSection(preview.files)
			Divider()
			readmeSection(repository: request.repository, isTruncated: preview.isReadmeTruncated)
		} else if completedRequest == request, let errorMessage {
			ContentUnavailableView {
				Label("Couldn’t Load Preview", systemImage: "exclamationmark.triangle")
			} description: {
				Text(errorMessage)
			} actions: {
				Button("Try Again") { refreshCount += 1 }
			}
		} else {
			ProgressView("Loading Preview…")
				.controlSize(.small)
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

	private func readmeSection(repository: GitHubRepository, isTruncated: Bool) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("README").font(.headline)
			if let readme {
				RepositoryReadmeView(content: readme)
				if isTruncated {
					Link("Read the Full README on GitHub", destination: repository.webURL)
				}
			} else {
				Text("No README available").foregroundStyle(.secondary)
			}
		}
	}

	private func loadPreview(for request: Request) async {
		let repository = request.repository
		if completedRequest?.repository.id != repository.id { showsAllFiles = false }
		do {
			let preview = try await accountViewModel.loadRepositoryPreview(
				for: repository, account: request.account)
			try Task.checkCancellation()
			readme = nil
			if let markdown = preview.readme, !markdown.isEmpty {
				let baseURL = repository.webURL
					.appending(
						path: "blob/\(repository.defaultBranch ?? "HEAD")", directoryHint: .isDirectory)
				readme =
					(try? AttributedString(
						markdown: markdown,
						baseURL: baseURL
					)) ?? AttributedString(markdown)
			}
			self.preview = preview
			completedRequest = request
		} catch is CancellationError {
			return
		} catch {
			guard !Task.isCancelled else { return }
			preview = nil
			readme = nil
			errorMessage = error.localizedDescription
			completedRequest = request
		}
	}
}
