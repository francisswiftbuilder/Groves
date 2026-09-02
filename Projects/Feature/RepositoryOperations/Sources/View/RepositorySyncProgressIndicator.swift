import SwiftUI

public struct RepositorySyncProgressIndicator: View {
	private let activity: RepositorySyncViewModel.Activity

	public init(activity: RepositorySyncViewModel.Activity) {
		self.activity = activity
	}

	public var body: some View {
		ProgressView()
			.controlSize(.small)
			.accessibilityLabel(activity.statusDescription)
			.help(activity.statusDescription)
	}
}
