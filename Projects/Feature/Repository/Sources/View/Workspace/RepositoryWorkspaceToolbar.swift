import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RepositoryWorkspaceToolbar: ToolbarContent {
	@ObservedObject var viewModel: WorkspaceViewModel
	let onCreateBranch: () -> Void

	var body: some ToolbarContent {
		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				onCreateBranch()
			} label: {
				Label("New Branch", systemImage: "arrow.triangle.branch")
			}
			.disabled(viewModel.isLoading || viewModel.currentBranch == nil)
			.help("Create a Branch from \(viewModel.currentBranchName)")

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
				Menu {
					Button("Fetch All Remotes", systemImage: "arrow.triangle.2.circlepath") {
						viewModel.didRequestFetchAll()
					}

					if !viewModel.remotes.isEmpty {
						Divider()
						ForEach(viewModel.remotes) { remote in
							Button(remote.name, systemImage: "icloud.and.arrow.down") {
								viewModel.didRequestFetch(remoteName: remote.name)
							}
						}
					}
				} label: {
					Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
				}
				.disabled(viewModel.remotes.isEmpty)
				.help("Fetch Remote References")

				Button {
					viewModel.didRequestPull()
				} label: {
					Label("Pull", systemImage: "arrow.down")
				}
				.help("Pull Current Branch")

				pushControl
			}
		}
	}

	@ViewBuilder
	private var pushControl: some View {
		switch viewModel.pushAction {
		case .chooseRemote(let remoteNames, _):
			Menu {
				ForEach(remoteNames, id: \.self) { remoteName in
					Button(remoteName, systemImage: "icloud.and.arrow.up") {
						viewModel.didRequestPush(remoteName: remoteName)
					}
				}
			} label: {
				Label("Push", systemImage: "arrow.up")
			}
			.help("Choose a Remote and Set Upstream")
		case .unavailable:
			Button {
			} label: {
				Label("Push", systemImage: "arrow.up")
			}
			.disabled(true)
			.help("No Local Branch Available to Push")
		case .upstream, .setUpstream:
			Button {
				viewModel.didRequestPush()
			} label: {
				Label("Push", systemImage: "arrow.up")
			}
			.help("Push Current Branch")
		}
	}
}
