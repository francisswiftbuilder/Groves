import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeHeader: View {
	let fileCount: Int

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text("Files").font(.headline)
				Spacer()
				Text("\(fileCount)").font(.caption).foregroundStyle(.secondary)
			}
			.padding(.horizontal, 12)
			.frame(height: 52)
			.background(.bar)
			Divider()
		}
	}
}
