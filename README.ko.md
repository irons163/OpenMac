# OpenMac

OpenMac은 macOS 중심의 AI 에이전트 Kanban 앱으로, 계획/할당/실행 워크플로를 한 곳에서 관리합니다.

## 언어

- [English](README.md)
- [繁體中文](README.zh-Hant.md)
- [简体中文](README.zh-Hans.md)
- [Français](README.fr.md)
- [Español](README.es.md)
- [日本語](README.ja.md)
- 한국어 (현재)

## 스크린샷

### Kanban 보드
![OpenMac Kanban Overview](docs/images/kanban-overview.jpg)

### Agent 실시간 콘솔
![OpenMac Agent Live Console](docs/images/agent-live-console.jpg)

## 주요 기능

- AI 에이전트 Kanban 흐름 (`To Do`, `In Progress`, `Review`, `Done`)
- 스킬/부하 기반 자동 할당
- 할당된 작업 일괄 실행 (`Run Assigned`)
- Runtime 옵션: `Local Mock`, `OpenAI Compatible`
- OpenAI 호환 인증: `API Key` 또는 `Codex Bridge`
- PM Planner:
  - 프로젝트 브리프에서 실행 가능한 티켓 생성
  - 생성 전 티켓 편집
  - 빠른 템플릿 (`SaaS Product`, `Desktop App`, `Developer API`)
  - `Create + Run Assigned` 플로우
- Agent Live Console (출력/디버그 로그 복사 지원)
- 보드 상태 권고, WIP 제한, 수동 트리아지
- 워크스페이스 JSON 가져오기/내보내기
- 다국어 UI (EN/ZH-TW/ZH-CN/FR/ES/JA/KO), 미지원 언어는 영어로 폴백

## 기술 스택

- Swift
- SwiftUI
- XCTest / Swift Testing
- Xcode 프로젝트 (`OpenMac.xcodeproj`)

## 프로젝트 구조

```text
OpenMac/
  Domain/         # 모델, 디스패치 로직, 플래닝 엔진
  ViewModels/     # 보드 오케스트레이션 및 runtime 통합
  Views/          # 재사용 가능한 SwiftUI 뷰
  Localization/   # 언어 설정 및 해석
  *.lproj/        # 로컬라이즈 문자열
OpenMacTests/     # 단위/로직 테스트
OpenMacUITests/   # UI 테스트
```

## 빠른 시작

1. 저장소를 클론합니다.
2. Xcode에서 `OpenMac.xcodeproj`를 엽니다.
3. scheme `OpenMac`을 선택합니다.
4. `My Mac`에서 실행합니다.

## AI Runtime 설정

### 옵션 A: API Key

- 환경 변수에 `OPENAI_API_KEY`(또는 `OPENAI_COMPAT_API_KEY`)를 설정합니다.
- OpenAI 호환 엔드포인트를 쓰는 경우 `OPENAI_BASE_URL`을 선택적으로 설정합니다.

### 옵션 B: Codex Bridge

1. Codex CLI 또는 Codex 앱을 설치합니다.
2. Terminal에서 `codex login`을 실행합니다.
3. 앱 runtime 설정에서 `OpenAI Compatible` + `Codex Bridge`를 선택합니다.

## 테스트 (TDD 친화)

전체 테스트 실행:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS'
```

특정 테스트 타깃만 실행:

```bash
xcodebuild test -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests
```

