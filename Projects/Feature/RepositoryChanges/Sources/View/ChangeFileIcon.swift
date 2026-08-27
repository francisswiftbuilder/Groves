import DomainGitInterface
import SwiftUI

struct ChangeFileIcon: View {
	let path: String

	var body: some View {
		Image(systemName: symbolName)
			.symbolRenderingMode(.hierarchical)
			.foregroundStyle(.secondary)
			.frame(width: 18, height: 18)
			.accessibilityHidden(true)
	}

	private var symbolName: String {
		switch URL(fileURLWithPath: path).pathExtension.lowercased() {
		case "swift":
			return "swift"
		case "xcassets":
			return "folder"
		case "md", "txt", "json", "plist", "yml", "yaml":
			return "doc.text"
		case "png", "jpg", "jpeg", "gif", "webp":
			return "photo"
		default:
			return "doc"
		}
	}
}
