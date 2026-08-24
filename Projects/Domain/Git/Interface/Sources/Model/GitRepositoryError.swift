import Foundation

public enum GitRepositoryError: LocalizedError, Sendable {
	case invalidRepository
	case invalidRemoteURL
	case repositoryAlreadyExists
	case commandFailed(String)
	case invalidOutput
	case invalidFilePath
	case fileUnavailable
	case fileTooLarge

	public var errorDescription: String? {
		switch self {
		case .invalidRepository:
			return "선택한 폴더는 Git 저장소가 아닙니다."
		case .invalidRemoteURL:
			return "올바른 Git 저장소 URL을 입력해 주세요."
		case .repositoryAlreadyExists:
			return "선택한 위치에 같은 이름의 폴더가 이미 있습니다."
		case .commandFailed(let message):
			return message.isEmpty ? "Git 명령을 실행하지 못했습니다." : message
		case .invalidOutput:
			return "Git 출력 형식을 해석하지 못했습니다."
		case .invalidFilePath:
			return "저장소 밖의 파일은 열 수 없습니다."
		case .fileUnavailable:
			return "파일을 읽을 수 없습니다."
		case .fileTooLarge:
			return "미리보기에는 파일이 너무 큽니다."
		}
	}
}
