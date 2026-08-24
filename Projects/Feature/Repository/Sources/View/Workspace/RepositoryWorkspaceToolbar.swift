import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RepositoryWorkspaceToolbar: ToolbarContent {
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
