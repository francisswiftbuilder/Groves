import SwiftUI

struct RepositoryPushMenu: View {
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	var preferredRemoteName: String?

	init(
		viewModel: RepositoryOperationViewModel,
		preferredRemoteName: String? = nil
	) {
		_operationViewModel = ObservedObject(wrappedValue: viewModel)
		self.preferredRemoteName = preferredRemoteName
	}

	var body: some View {
		Menu {
			branchPushControl(forceWithLease: false)
			branchPushControl(forceWithLease: true)

			Divider()

			tagPushControl
		} label: {
			Label("Push", systemImage: "arrow.up")
		}
		.accessibilityLabel("Push")
		.disabled(operationViewModel.isLoading || !hasAvailableAction)
		.help("Push Current Branch or Tags")
	}

	private var hasAvailableAction: Bool {
		operationViewModel.pushAction != .unavailable || !availableRemoteNames.isEmpty
	}

	private var availableRemoteNames: [String] {
		if let preferredRemoteName,
			operationViewModel.remotes.contains(where: { $0.name == preferredRemoteName })
		{
			return [preferredRemoteName]
		}
		return operationViewModel.remotes.map(\.name)
	}

	@ViewBuilder
	private func branchPushControl(forceWithLease: Bool) -> some View {
		let title = forceWithLease ? "Force Push with Lease…" : "Push Current Branch"
		let systemImage = forceWithLease ? "exclamationmark.triangle" : "arrow.up"

		switch operationViewModel.pushAction {
		case .chooseRemote(let remoteNames, _):
			Menu(title, systemImage: systemImage) {
				ForEach(remoteNames.filter(isAvailableRemote), id: \.self) { remoteName in
					Button(remoteName, systemImage: "icloud.and.arrow.up") {
						requestBranchPush(
							remoteName: remoteName,
							forceWithLease: forceWithLease
						)
					}
				}
			}
		case .unavailable:
			Button {
			} label: {
				Label(title, systemImage: systemImage)
			}
			.disabled(true)
		case .upstream, .setUpstream:
			Button {
				requestBranchPush(
					remoteName: preferredRemoteName,
					forceWithLease: forceWithLease
				)
			} label: {
				Label(title, systemImage: systemImage)
			}
		}
	}

	@ViewBuilder
	private var tagPushControl: some View {
		switch availableRemoteNames.count {
		case 0:
			Button("Push All Tags", systemImage: "tag") {}
				.disabled(true)
		case 1:
			if let remoteName = availableRemoteNames.first {
				Button("Push All Tags to \(remoteName)", systemImage: "tag") {
					operationViewModel.didRequestPushTags(remoteName: remoteName)
				}
			}
		default:
			Menu("Push All Tags", systemImage: "tag") {
				ForEach(availableRemoteNames, id: \.self) { remoteName in
					Button(remoteName, systemImage: "icloud.and.arrow.up") {
						operationViewModel.didRequestPushTags(remoteName: remoteName)
					}
				}
			}
		}
	}

	private func isAvailableRemote(_ remoteName: String) -> Bool {
		preferredRemoteName == nil || preferredRemoteName == remoteName
	}

	private func requestBranchPush(remoteName: String?, forceWithLease: Bool) {
		if forceWithLease {
			operationViewModel.didPresentForcePushConfirmation(remoteName: remoteName)
		} else {
			operationViewModel.didRequestPush(remoteName: remoteName)
		}
	}
}
