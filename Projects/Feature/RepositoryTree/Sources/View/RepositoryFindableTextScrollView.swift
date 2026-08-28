import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

final class RepositoryFindableTextScrollView: NSScrollView {
	let textView = NSTextView()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		documentView = textView
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError()
	}

	override func layout() {
		super.layout()
		updateDocumentSize()
	}

	func updateDocumentSize() {
		guard
			let textContainer = textView.textContainer,
			let layoutManager = textView.layoutManager
		else { return }

		layoutManager.ensureLayout(for: textContainer)
		let usedRect = layoutManager.usedRect(for: textContainer)
		let inset = textView.textContainerInset
		let viewportSize = contentView.bounds.size
		let documentSize = NSSize(
			width: max(viewportSize.width, ceil(usedRect.width + inset.width * 2)),
			height: max(viewportSize.height, ceil(usedRect.height + inset.height * 2))
		)

		guard textView.frame.size != documentSize else { return }
		textView.setFrameSize(documentSize)
	}
}
