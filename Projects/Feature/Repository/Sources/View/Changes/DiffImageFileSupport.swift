import Foundation
import UniformTypeIdentifiers

enum DiffImageFileSupport {
	static func isSupported(path: String) -> Bool {
		let fileExtension = URL(fileURLWithPath: path).pathExtension
		guard !fileExtension.isEmpty,
			let type = UTType(filenameExtension: fileExtension)
		else { return false }
		return type.conforms(to: .image)
	}
}
