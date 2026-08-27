import Foundation

extension String {
	func removingPrefix(_ prefix: String) -> String? {
		guard hasPrefix(prefix) else { return nil }
		return String(dropFirst(prefix.count))
	}
}
