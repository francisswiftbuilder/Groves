import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeGuide: View {
	let item: RepositoryTreeItem

	private let indentation: CGFloat = 16

	var body: some View {
		Canvas { context, size in
			guard item.depth > 0 else { return }
			let color = Color(nsColor: .separatorColor).opacity(0.7)
			let rowMidY = size.height / 2

			if item.depth > 1 {
				for level in 0..<(item.depth - 1)
				where item.ancestorHasFollowingSibling[level] {
					let x = CGFloat(level) * indentation + indentation / 2
					var path = Path()
					path.move(to: CGPoint(x: x, y: 0))
					path.addLine(to: CGPoint(x: x, y: size.height))
					context.stroke(path, with: .color(color), lineWidth: 1)
				}
			}

			let branchX = CGFloat(item.depth - 1) * indentation + indentation / 2
			var branch = Path()
			branch.move(to: CGPoint(x: branchX, y: 0))
			branch.addLine(
				to: CGPoint(
					x: branchX,
					y: item.isLastSibling ? rowMidY : size.height
				)
			)
			branch.move(to: CGPoint(x: branchX, y: rowMidY))
			branch.addLine(to: CGPoint(x: size.width, y: rowMidY))
			context.stroke(branch, with: .color(color), lineWidth: 1)
		}
		.frame(width: CGFloat(item.depth) * indentation, height: 24)
		.accessibilityHidden(true)
	}
}
