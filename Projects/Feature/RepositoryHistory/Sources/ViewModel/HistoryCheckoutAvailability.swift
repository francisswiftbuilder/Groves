import Combine

@MainActor
public final class HistoryCheckoutAvailability: ObservableObject {
	@Published public private(set) var hasWorkingTreeChanges = false

	func apply(hasWorkingTreeChanges: Bool) {
		guard self.hasWorkingTreeChanges != hasWorkingTreeChanges else { return }
		self.hasWorkingTreeChanges = hasWorkingTreeChanges
	}
}
