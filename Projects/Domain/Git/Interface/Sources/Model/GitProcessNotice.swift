import Foundation

public enum GitProcessNotice: Hashable, Sendable {
	case credentialPersistenceFailed

	public var message: String {
		switch self {
		case .credentialPersistenceFailed:
			return "Git 작업은 완료했지만 자격증명을 키체인에 저장하지 못했습니다. "
				+ "다음 작업에서 다시 인증을 요청할 수 있습니다. Settings에서 저장된 자격증명을 확인해 주세요."
		}
	}
}
