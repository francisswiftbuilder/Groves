import SwiftUI

struct HostedRepositoryRootView: View {
	@State private var repositoryID: UUID?
	private let makeRootView: @MainActor (Binding<UUID?>) -> AnyView

	init(
		initialRepositoryID: UUID?,
		makeRootView: @escaping @MainActor (Binding<UUID?>) -> AnyView
	) {
		_repositoryID = State(initialValue: initialRepositoryID)
		self.makeRootView = makeRootView
	}

	var body: some View {
		makeRootView($repositoryID)
	}
}
