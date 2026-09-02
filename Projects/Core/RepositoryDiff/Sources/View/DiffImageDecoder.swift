import AppKit
import Foundation
import ImageIO

enum DiffImageDecoder {
	static func decode(_ data: Data?, maximumPixelSize: CGFloat = 2_560) async -> NSImage? {
		guard let data else { return nil }
		let worker = Task.detached(priority: .userInitiated) { () -> NSImage? in
			guard !Task.isCancelled else { return nil }
			let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
			guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
				return NSImage(data: data)
			}
			let thumbnailOptions =
				[
					kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
					kCGImageSourceCreateThumbnailWithTransform: true,
					kCGImageSourceShouldCacheImmediately: true,
				] as CFDictionary
			guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
				return NSImage(data: data)
			}
			guard !Task.isCancelled else { return nil }
			return NSImage(cgImage: image, size: .zero)
		}
		return await withTaskCancellationHandler {
			await worker.value
		} onCancel: {
			worker.cancel()
		}
	}
}
