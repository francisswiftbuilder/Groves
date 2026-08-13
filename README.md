# Trees

Swift와 SwiftUI로 만든 macOS 전용 Git GUI입니다.

## 요구 사항

- macOS 26 이상
- Swift 6 툴체인
- Xcode
- Tuist 4.166 이상

## 구조

- `Projects/App`: 앱 진입점과 Composition Root
- `Projects/Feature/Repository`: 변경 사항, 커밋 그래프, 브랜치, 태그, 파일 트리 UI
- `Projects/Domain/Git`: Git 모델과 저장소 인터페이스
- `Projects/Data/Git`: Git 프로세스 실행과 출력 파싱
- `Tuist/ProjectDescriptionHelpers`: 모듈, 타깃, 의존성 생성 정의
- `Tuist/Plugins`: 로컬 Tuist 플러그인
- `Tuist/Scripts`: 모듈, 타깃, 스킴 동기화 스크립트

## 명령어

```bash
make generate
make module
make sync
make clean
```

프로젝트를 생성한 뒤 `Trees.xcworkspace`의 `App` 스킴을 실행합니다.

추가한 저장소와 마지막 선택 탭은 SwiftData에 저장되며, 저장소 접근 권한은 security-scoped bookmark로 복원됩니다.
