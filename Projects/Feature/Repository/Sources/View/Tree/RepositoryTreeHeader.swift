import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeHeader: View {
	let statistics: (directories: Int, files: Int)

	var body: some View {
		HStack(spacing: 10) {
			Label("\(statistics.directories) folders", systemImage: "folder")
			Label("\(statistics.files) files", systemImage: "doc")
				.foregroundStyle(.secondary)
			Spacer()
		}
		.font(.caption)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.bar)
	}
}
