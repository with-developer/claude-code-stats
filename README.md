# Claude Code Stats

macOS 메뉴바에서 Claude Code 사용량을 실시간으로 모니터링하는 앱입니다.

## Menu Bar Display

```
┌──────────────┐
│  5H    7D    │  ← 라벨 (5Hour, 7Day)
│ 83%   89%    │  ← 남은 사용량
└──────────────┘
```

클릭하면 세션/주간/모델별 상세 사용량, 리셋 시간, 프로그레스 바를 팝오버로 표시합니다.

## Features

- **메뉴바 직접 표시** - 클릭 없이 세션(5H), 주간(7D) 남은 퍼센트 확인
- **상세 팝오버** - 세션/주간/Opus/Sonnet별 프로그레스 바 & 리셋 시간
- **OAuth API 우선** - `api.anthropic.com/api/oauth/usage`로 조회, 실패 시 CLI 폴백
- **자동 갱신** - 30초~5분 간격 설정 가능
- **다크/라이트 모드** - 템플릿 이미지로 자동 대응

## Data Source

1. **OAuth API** (우선) - macOS Keychain에서 Claude Code 인증 토큰을 읽어 API 호출
2. **CLI 폴백** - `claude -p "/usage"`로 사용량 파싱

## Requirements

- macOS 14.0 (Sonoma) 이상
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 설치 및 로그인 필요
- Swift 5.9+

## Build & Run

```bash
./build.sh
open ClaudeCodeStats.app

# Applications에 설치
cp -r ClaudeCodeStats.app /Applications/
```

## Architecture

```
Sources/ClaudeCodeStats/
├── main.swift              # App entry point (menu bar only, no Dock icon)
├── AppDelegate.swift       # NSStatusItem & menu bar rendering
├── MenuBarView.swift       # SwiftUI popover with detailed usage rows
├── ClaudeUsageParser.swift # OAuth API + CLI fetching & parsing
└── UsageStore.swift        # Observable state & auto-refresh timer
```

## License

MIT
