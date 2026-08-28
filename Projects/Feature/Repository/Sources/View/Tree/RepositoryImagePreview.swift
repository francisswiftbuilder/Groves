import AppKit
import CoreRepositoryUI
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryImagePreview: View {
	let data: Data

	var body: some View {
		if let image = NSImage(data: data) {
			Image(nsImage: image)
				.resizable()
				.scaledToFit()
				.padding(24)
				.accessibilityLabel("Image Preview")
		} else {
			EmptyStateView(
				title: "Preview Unavailable",
				message: "The image format could not be decoded.",
				systemImage: "photo.badge.exclamationmark"
			)
		}
	}
}
