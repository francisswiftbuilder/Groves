import SwiftUI

public struct RepositorySyncCancelButton: View {
	@ObservedObject private var viewModel: RepositorySyncViewModel

	public init(viewModel: RepositorySyncViewModel) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
	}

	public var body: some View {
		Button {
			viewModel.didRequestCancelOperation()
		} label: {
			Label(cancellationLabel, systemImage: "stop.fill")
		}
		.accessibilityLabel(cancellationLabel)
		.help("\(cancellationLabel) — \(statusDescription)")
	}

	private var cancellationLabel: String {
		viewModel.presentedActivity?.cancellationLabel ?? "Cancel Git Operation"
	}

	private var statusDescription: String {
		viewModel.presentedActivity?.statusDescription ?? "Git operation in progress"
	}
}
