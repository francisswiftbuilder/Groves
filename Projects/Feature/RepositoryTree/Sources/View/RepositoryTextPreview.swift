import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTextPreview: View {
	let content: String

	var body: some View {
		RepositoryFindableTextView(content: content)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}
