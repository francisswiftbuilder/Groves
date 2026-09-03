import Foundation

public enum SavedRepositoryStoreError: LocalizedError, Sendable {
	case bookmarkCreationFailed
	case bookmarkResolutionFailed
	case persistenceFailed

	public var errorDescription: String? {
		switch self {
		case .bookmarkCreationFailed:
			return "저장소 접근 정보를 만들지 못했습니다."
		case .bookmarkResolutionFailed:
			return "저장된 저장소 위치에 접근하지 못했습니다."
		case .persistenceFailed:
			return "저장소 목록을 저장하지 못했습니다."
		}
	}
}
