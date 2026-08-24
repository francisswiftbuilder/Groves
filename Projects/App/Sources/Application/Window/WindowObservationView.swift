import AppKit
import SwiftUI

final class WindowObservationView: NSView {
	var didMoveToWindow: (NSWindow?) -> Void = { _ in }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		didMoveToWindow(window)
	}
}
