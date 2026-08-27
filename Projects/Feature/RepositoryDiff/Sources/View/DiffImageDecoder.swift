import AppKit
import Foundation
import ImageIO

enum DiffImageDecoder {
	static func decode(_ data: Data?, maximumPixelSize: CGFloat = 2_560) async -> NSImage? {
		guard let data else { return nil }
		return await Task.detached(priority: .userInitiated) {
			let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
			guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
				return nil
			}
			let thumbnailOptions =
				[
					kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
					kCGImageSourceCreateThumbnailWithTransform: true,
					kCGImageSourceShouldCacheImmediately: true,
				] as CFDictionary
			guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
				return nil
			}
			return NSImage(cgImage: image, size: .zero)
		}.value
	}
}
