import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeRow: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let item: RepositoryTreeItem
	@Binding var expandedNodeIDs: Set<String>
	let onSelect: () -> Void

	private var isExpanded: Bool {
		expandedNodeIDs.contains(item.id)
	}

	var body: some View {
		HStack(spacing: 6) {
			RepositoryTreeGuide(item: item)

			if item.node.isDirectory {
				Button(action: toggleExpansion) {
					Image(systemName: "chevron.right")
						.font(.system(size: 9, weight: .semibold))
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.frame(width: 12, height: 18)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(isExpanded ? "Collapse \(item.node.name)" : "Expand \(item.node.name)")
			} else {
				Color.clear
					.frame(width: 12, height: 18)
					.accessibilityHidden(true)
			}

			Image(systemName: symbolName)
				.foregroundStyle(symbolColor)
				.frame(width: 17)
				.accessibilityHidden(true)

			Text(item.node.name)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer(minLength: 8)

			if item.node.isDirectory {
				Text(item.node.children.count, format: .number)
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.tertiary)
			}
		}
		.frame(minHeight: 24)
		.contentShape(.rect)
		.simultaneousGesture(
			TapGesture()
				.onEnded {
					Task { @MainActor in
						await Task.yield()
						onSelect()
					}
				}
		)
		.simultaneousGesture(
			TapGesture(count: 2)
				.onEnded {
					guard item.node.isDirectory else { return }
					Task { @MainActor in
						await Task.yield()
						toggleExpansion()
					}
				}
		)
		.help(item.node.path)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
	}

	private var accessibilityLabel: String {
		if item.node.isDirectory {
			return "\(item.node.name), folder, \(item.node.children.count) items"
		}
		return "\(item.node.name), file"
	}

	private var symbolName: String {
		if item.node.isDirectory {
			return "folder.fill"
		}

		switch item.node.name.split(separator: ".").last?.lowercased() {
		case "swift":
			return "swift"
		case "md", "markdown", "rtf":
			return "doc.richtext"
		case "json", "plist", "yaml", "yml":
			return "curlybraces"
		case "png", "jpg", "jpeg", "gif", "heic", "svg":
			return "photo"
		case "sh", "zsh", "bash":
			return "terminal"
		default:
			return "doc.text"
		}
	}

	private var symbolColor: Color {
		if item.node.isDirectory {
			return .accentColor
		}
		if item.node.name.hasSuffix(".swift") {
			return .orange
		}
		return .secondary
	}

	private func toggleExpansion() {
		let animation: Animation =
			reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
		withAnimation(animation) {
			if isExpanded {
				expandedNodeIDs.remove(item.id)
			} else {
				expandedNodeIDs.insert(item.id)
			}
		}
	}
}
