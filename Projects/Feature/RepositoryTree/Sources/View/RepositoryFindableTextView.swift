import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryFindableTextView: NSViewRepresentable {
	let content: String

	func makeNSView(context: Context) -> RepositoryFindableTextScrollView {
		let scrollView = RepositoryFindableTextScrollView()
		let textView = scrollView.textView

		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true

		textView.isEditable = false
		textView.isSelectable = true
		textView.isRichText = false
		textView.drawsBackground = false
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
		textView.textColor = .labelColor
		textView.textContainerInset = NSSize(width: 16, height: 16)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = true
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.containerSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.string = content
		textView.setAccessibilityLabel("File Contents")
		scrollView.updateDocumentSize()

		return scrollView
	}

	func updateNSView(_ scrollView: RepositoryFindableTextScrollView, context: Context) {
		let textView = scrollView.textView
		guard textView.string != content else { return }

		textView.string = content
		scrollView.updateDocumentSize()
		textView.scrollToBeginningOfDocument(nil)
	}
}
