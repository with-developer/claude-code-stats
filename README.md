# Claude Code Stats

macOS 메뉴바에서 Claude Code 사용량을 실시간으로 모니터링하는 앱입니다.

## Menu Bar Display

두 가지 스타일을 지원합니다:

**Compact** - 퍼센트 + 리셋 시간 (2행)
```
┌──────────────┐
│  95%   88%   │  ← 남은 사용량
│ 4h31m 2d22h  │  ← 리셋까지 남은 시간
└──────────────┘
```

**Inline** - 한 줄 표시
```
95%4h31m  88%2d22h
```

사용량이 30% 미만이면 노란색, 15% 미만이면 빨간색으로 경고 표시됩니다.

## Popover

클릭하면 세션/주간/Sonnet별 상세 사용량을 큰 숫자 카드와 프로그레스 바로 표시합니다.
라이트/다크 모드에 맞춰 색상이 자동 조정됩니다.

## Features

- **메뉴바 직접 표시** - 클릭 없이 세션, 주간 남은 퍼센트 + 리셋 시간 확인
- **스타일 선택** - Compact / Inline 전환 가능
- **상세 팝오버** - 세션/주간/Sonnet별 프로그레스 바 & 리셋 시간
- **자동 갱신** - 3분/5분(기본)/10분 간격 설정
- **다크/라이트 모드** - 자동 대응
- **경고 색상** - 사용량 낮을 때 노란색/빨간색 표시

## Data Source

**OAuth API** - `api.anthropic.com/api/oauth/usage`로 조회

토큰 읽기 순서:
1. 환경변수 `CLAUDE_OAUTH_TOKEN`
2. `~/.claude/.stats-token-cache` (빌드 시 캐시)
3. `~/.claude/.credentials.json`

키체인에 직접 접근하지 않으므로 macOS 권한 팝업이 발생하지 않습니다.

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
├── AppDelegate.swift       # NSStatusItem & menu bar rendering (Compact/Inline)
├── MenuBarView.swift       # SwiftUI popover (Design E, adaptive theme)
├── ClaudeUsageParser.swift # OAuth API fetching & parsing (no subprocess)
└── UsageStore.swift        # Observable state, auto-refresh, style settings
```

## License

MIT
