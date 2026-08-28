import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

enum RepositoryFilePreview: Equatable, Sendable {
	case none
	case loading
	case text(content: String, byteCount: Int)
	case image(data: Data)
	case unsupported(byteCount: Int)
	case failure(String)

	private static let maximumTextByteCount = 2 * 1_024 * 1_024

	var byteCount: Int? {
		switch self {
		case .text(_, let byteCount), .unsupported(let byteCount):
			return byteCount
		case .image(let data):
			return data.count
		case .none, .loading, .failure:
			return nil
		}
	}

	static func make(path: String, data: Data) -> RepositoryFilePreview {
		let pathExtension = URL(fileURLWithPath: path).pathExtension
		if UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true {
			return .image(data: data)
		}

		guard
			data.count <= maximumTextByteCount,
			!data.contains(0),
			let content = String(data: data, encoding: .utf8)
		else {
			return .unsupported(byteCount: data.count)
		}

		return .text(content: content, byteCount: data.count)
	}
}
