# Claude Code Stats

macOS 메뉴바에서 Claude Code 사용량을 실시간으로 모니터링하는 앱입니다.
[Stats](https://github.com/exelban/stats) 앱처럼 컴팩트한 바 형태로 사용률을 표시합니다.

## Features

- **세션 사용량** - 현재 세션의 남은 사용량 (5시간 윈도우)
- **주간 사용량** - 주간 전체 모델 남은 사용량
- **Opus/Sonnet 사용량** - 모델별 주간 남은 사용량
- **자동 갱신** - 30초~5분 간격으로 설정 가능
- **리셋 시간 표시** - 각 제한의 리셋 시점 확인
- **컴팩트 메뉴바 표시** - Stats 앱 스타일의 수직 바 아이콘
- **색상 코드** - 초록(충분) → 노랑(보통) → 주황(주의) → 빨강(위험)

## Requirements

- macOS 14.0 (Sonoma) 이상
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 설치 필요
- Swift 5.9+

## Build & Run

```bash
# 빌드
./build.sh

# 실행
open ClaudeCodeStats.app

# 또는 Applications에 설치
cp -r ClaudeCodeStats.app /Applications/
```

## How It Works

1. Claude Code CLI (`claude --print-usage`)를 주기적으로 호출
2. 출력에서 세션/주간 사용률 퍼센트를 파싱
3. macOS 메뉴바에 컴팩트한 수직 바로 표시
4. 클릭하면 상세 정보 팝오버 표시

### Menu Bar Display

```
┌─────────┐
│ ▌▌▌     │  ← S(Session), W(Weekly), O(Opus) 바
└─────────┘
```

- 초록색 바 = 60%+ 남음
- 노란색 바 = 30-60% 남음
- 주황색 바 = 15-30% 남음
- 빨간색 바 = 15% 미만

## Architecture

```
Sources/ClaudeCodeStats/
├── main.swift              # App entry point
├── AppDelegate.swift       # Menu bar status item & icon rendering
├── MenuBarView.swift       # SwiftUI views for popover & bars
├── ClaudeUsageParser.swift # CLI output parsing & data fetching
└── UsageStore.swift        # Observable state management
```

## Inspired By

- [CodexBar](https://github.com/steipete/codexbar) - AI 코딩 어시스턴트 사용량 모니터
- [Stats](https://github.com/exelban/stats) - macOS 시스템 모니터

## License

MIT
