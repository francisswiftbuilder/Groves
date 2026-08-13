import SwiftUI
import UniformTypeIdentifiers

struct RepositoryTabsView: View {
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@State private var isRepositoryImporterPresented = false

	var body: some View {
		Group {
			if let workspace = viewModel.selectedWorkspace {
				WorkspaceView(
					viewModel: workspace,
					repositories: viewModel.tabs,
					selectedRepositoryID: viewModel.selectedTabID,
					onSelectRepository: viewModel.didSelectTab,
					onCloseRepository: viewModel.didRequestCloseTab,
					onAddRepository: presentRepositoryImporter
				)
			} else {
				EmptyStateView(
					title: "Open a Git Repository",
					message: "Add repositories and return to them whenever you open Trees.",
					systemImage: "rectangle.stack.badge.plus",
					actionTitle: "Add Repository",
					actionSystemImage: "plus",
					action: presentRepositoryImporter
				)
			}
		}
		.toolbar {
			if let workspace = viewModel.selectedWorkspace {
				RepositoryWorkspaceToolbar(viewModel: workspace)
			}
		}
		.toolbarRole(.editor)
		.fileImporter(
			isPresented: $isRepositoryImporterPresented,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: false
		) { result in
			switch result {
			case .success(let urls):
				if let url = urls.first {
					viewModel.didChooseRepository(url)
				}
			case .failure(let error):
				viewModel.alertMessage = error.localizedDescription
			}
		}
		.alert(
			"Repository Error",
			isPresented: Binding(
				get: { viewModel.alertMessage != nil },
				set: { isPresented in
					if !isPresented {
						viewModel.alertMessage = nil
					}
				}
			),
			actions: {
				Button("OK") {
					viewModel.alertMessage = nil
				}
			},
			message: {
				Text(viewModel.alertMessage ?? "")
			}
		)
	}

	private func presentRepositoryImporter() {
		isRepositoryImporterPresented = true
	}
}

private struct RepositoryWorkspaceToolbar: ToolbarContent {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some ToolbarContent {
		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				viewModel.didRequestRefresh()
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.buttonBorderShape(.circle)
			.disabled(viewModel.isLoading)
			.help("Refresh Repository")

			if viewModel.isLoading {
				ProgressView()
					.controlSize(.small)
					.accessibilityLabel("Git operation in progress")
			} else {
				Button {
					viewModel.didRequestPull()
				} label: {
					Label("Pull", systemImage: "arrow.down")
				}
				.help("Pull Current Branch")

				Button {
					viewModel.didRequestPush()
				} label: {
					Label("Push", systemImage: "arrow.up")
				}
				.help("Push Current Branch")
			}
		}
	}
}
