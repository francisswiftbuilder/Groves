actor GitRepositoryRecorder {
	private var events: [GitRepositoryRecorderEvent] = []

	func record(_ event: GitRepositoryRecorderEvent) {
		events.append(event)
	}

	func recordedEvents() -> [GitRepositoryRecorderEvent] {
		events
	}
}
