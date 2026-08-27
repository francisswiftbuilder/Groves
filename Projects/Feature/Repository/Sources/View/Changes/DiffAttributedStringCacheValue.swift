import Foundation

final class DiffAttributedStringCacheValue: NSObject {
	let value: AttributedString

	init(_ value: AttributedString) {
		self.value = value
	}
}
