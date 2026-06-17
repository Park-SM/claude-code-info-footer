[English](README.md) | <ins>한국어</ins>

# Claude Code Statusline

Claude Code 터미널 프롬프트 입력창 위에 3줄 상태바를 추가합니다.

```
◈ env    Opus 4.6 | ⧉ my-project | ⎇ feature/login
◷ usage  $1.23 | session 73% left | weekly 88% left | turn:12   ← 구독제(Pro/Max)
◷ usage  $1.23 | in:85k out:12k | turn:12                       ← API 플랜
◐ memory [████████░░░░░░░░░░░░] 40% NORMAL | cache:85%
```

## 동작 원리

Claude Code의 [statusLine](https://docs.claude.com/en/docs/claude-code/statusline) 기능을 사용합니다.
매 렌더링마다 Claude Code가 세션 정보(JSON)를 `statusline-command.sh`의 stdin으로 넘기고,
스크립트가 출력한 텍스트가 프롬프트 입력창 위에 표시됩니다.

- `statusline-command.sh` — JSON을 `jq`로 파싱해 3줄을 출력. git 브랜치는 `git symbolic-ref`로 조회.
- `parse-transcript.sh` — `Stop` hook. 턴 종료 시 transcript를 파싱해 세션별 누적 토큰/비용을
  `~/.claude/token-tracker/<session_id>.json`에 기록 (usage 줄 계산용).

## 줄별 설명

### `env` — 작업 환경 정보
| 항목 | 색상 | 설명 |
|------|------|------|
| model | lavender | 사용 중인 Claude 모델명 |
| project | mint | 현재 작업 디렉토리 이름 |
| ⎇ branch | warm tan | 현재 git 브랜치 (detached면 short SHA, git repo 아니면 숨김) |

### `memory` — context window 실시간 상태
| 항목 | 색상 | 설명 |
|------|------|------|
| gauge | 상태별 변동 | context 사용률 게이지 바 + % + 상태 라벨 (세션 초반엔 0%로 표시) |
| cache | sky blue | 직전 API 호출의 프롬프트 캐시 적중률 |

게이지 색상/라벨은 사용률에 따라 변합니다:

| 상태 | 범위 | 색상 |
|------|------|------|
| GOOD | < 30% | green |
| NORMAL | 30~50% | blue |
| WARNING | 50~80% | yellow |
| DANGER | >= 80% | red |

### `usage` — 사용량 (플랜에 따라 표기 분기)
> 직전 턴 기준입니다. 현재 턴은 응답 완료 후 반영됩니다.

`$` 비용은 항상 표기하고, 뒤쪽은 플랜에 따라 달라집니다.

**구독제 (Pro/Max)** — `rate_limits`가 내려오면 잔여 usage 표기:

| 항목 | 색상 | 설명 |
|------|------|------|
| $ | pink | 비용 (Opus 단가 기준 추정치) |
| session N% left | teal | 세션(5시간 단위) rate limit 잔여율 |
| weekly N% left | peach | 주간(7일) rate limit 잔여율 |
| turn | sky blue | 총 대화 턴 수 |

**API 플랜** — `rate_limits`가 없으면 토큰 표기:

| 항목 | 색상 | 설명 |
|------|------|------|
| $ | pink | API 환산 비용 (Opus 단가 기준 추정치) |
| in/out | teal | 누적 입력/출력 토큰 (k = 1,000) |
| turn | peach | 총 대화 턴 수 |

> 플랜 판별은 `rate_limits` 객체 유무로 합니다. 이 객체는 Claude.ai 구독자에게만,
> 그리고 세션 첫 API 응답 **이후**에 내려옵니다. 따라서 구독제라도 첫 응답 전까지는
> 잠깐 API 표기(in/out)가 보일 수 있습니다.

> 비용은 Opus 4 단가(input $15/M, output $75/M, cache_write $18.75/M, cache_read $1.875/M)로
> 환산한 **추정치**이며 실제 청구액과 다를 수 있습니다.

## Claude Code에게 설치 맡기기

직접 설정하지 않고, Claude Code에게 아래처럼 자연어로 요청해도 됩니다.
저장소 URL을 함께 전달하면 clone부터 `settings.json` 병합까지 알아서 처리합니다.

```
아래 저장소를 내 홈 디렉토리에 clone하고, statusLine으로 쓰도록 설정해줘.
https://github.com/Park-SM/claude-code-statusline

- $HOME/claude-code-statusline 로 clone하고 *.sh 에 실행 권한을 줘
- ~/.claude/settings.json 의 statusLine 을 statusline-command.sh 로 설정해줘
- Stop 훅에 parse-transcript.sh 를 등록해줘
- 기존 settings.json 내용은 지우지 말고 병합만 해줘
```

설정이 끝나면 **Claude Code를 재시작**하면 적용됩니다.
직접 설정하고 싶다면 아래 수동 설치를 따르세요.

## 수동 설치

1) 저장소를 `$HOME` 아래로 clone 합니다 (다른 위치에 두면 아래 경로만 맞춰주세요):

```sh
git clone git@github.com:Park-SM/claude-code-statusline.git "$HOME/claude-code-statusline"
chmod +x "$HOME/claude-code-statusline/"*.sh
```

2) `~/.claude/settings.json`에 아래 두 항목을 병합합니다. statusLine 커맨드는
셸로 실행되므로 `$HOME`이 전개됩니다.

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/claude-code-statusline/statusline-command.sh",
    "padding": 0
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/claude-code-statusline/parse-transcript.sh"
          }
        ]
      }
    ]
  }
}
```

설정 후 **Claude Code를 재시작**하면 적용됩니다.

## 요구사항

- Claude Code CLI
- `jq` (JSON 처리)
- `git` (브랜치 표시용 — 없거나 git repo가 아니면 브랜치만 숨김)
- 256색 + 유니코드(█ ░ ⎇)를 지원하는 터미널
