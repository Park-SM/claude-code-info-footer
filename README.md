<ins>English</ins> | [한국어](README.ko.md)

# Claude Code Statusline

Adds a 3-line status bar above the Claude Code terminal prompt input.

```
◈ env    Opus 4.6 | ⧉ my-project | ⎇ feature/login
◷ usage  $1.23 | session 73% left | weekly 88% left | turn:12   ← subscription (Pro/Max)
◷ usage  $1.23 | in:85k out:12k | turn:12                       ← API plan
◐ memory [████████░░░░░░░░░░░░] 40% NORMAL | cache:85%
```

## How it works

It uses Claude Code's [statusLine](https://docs.claude.com/en/docs/claude-code/statusline) feature.
On every render, Claude Code passes session info (JSON) to `statusline-command.sh` via stdin,
and the text the script prints is shown above the prompt input.

- `statusline-command.sh` — parses the JSON with `jq` and prints 3 lines. The git branch is read via `git symbolic-ref`.
- `parse-transcript.sh` — a `Stop` hook. On turn end it parses the transcript and records cumulative
  per-session tokens/cost to `~/.claude/token-tracker/<session_id>.json` (used to compute the usage line).

## Line-by-line

### `env` — working environment
| Item | Color | Description |
|------|-------|-------------|
| model | lavender | the Claude model in use |
| project | mint | current working directory name |
| ⎇ branch | warm tan | current git branch (short SHA if detached, hidden if not a git repo) |

### `memory` — live context window state
| Item | Color | Description |
|------|-------|-------------|
| gauge | varies by state | context usage gauge bar + % + state label (shows 0% early in the session) |
| cache | sky blue | prompt cache hit rate of the previous API call |

The gauge color/label changes with usage:

| State | Range | Color |
|-------|-------|-------|
| GOOD | < 30% | green |
| NORMAL | 30–50% | blue |
| WARNING | 50–80% | yellow |
| DANGER | >= 80% | red |

### `usage` — usage (display branches by plan)
> Reflects the previous turn. The current turn is applied after the response completes.

The `$` cost is always shown; the rest depends on the plan.

**Subscription (Pro/Max)** — when `rate_limits` is present, shows remaining usage:

| Item | Color | Description |
|------|-------|-------------|
| $ | pink | cost (estimate based on Opus pricing) |
| session N% left | teal | remaining session (5-hour window) rate limit |
| weekly N% left | peach | remaining weekly (7-day) rate limit |
| turn | sky blue | total conversation turns |

**API plan** — when `rate_limits` is absent, shows tokens:

| Item | Color | Description |
|------|-------|-------------|
| $ | pink | API-equivalent cost (estimate based on Opus pricing) |
| in/out | teal | cumulative input/output tokens (k = 1,000) |
| turn | peach | total conversation turns |

> Plan detection is based on whether the `rate_limits` object is present. It is sent only to
> Claude.ai subscribers, and only **after** the first API response of a session. So even on a
> subscription, you may briefly see the API display (in/out) before the first response.

> Cost is an **estimate** converted using Opus 4 pricing (input $15/M, output $75/M,
> cache_write $18.75/M, cache_read $1.875/M) and may differ from your actual bill.

## Let Claude Code install it

Instead of configuring it yourself, you can just ask Claude Code in natural language.
Pass the repository URL and it will handle everything from clone to merging `settings.json`.

```
Clone the repo below into my home directory and set it up as my statusLine.
https://github.com/Park-SM/claude-code-statusline

- Clone into $HOME/claude-code-statusline and make the *.sh files executable
- Set statusLine in ~/.claude/settings.json to statusline-command.sh
- Register parse-transcript.sh as a Stop hook
- Don't wipe my existing settings.json — merge only
```

Once it's done, **restart Claude Code** to apply it.
If you'd rather configure it yourself, follow the manual install below.

## Manual install

1) Clone the repo under `$HOME` (if you put it elsewhere, just adjust the paths below):

```sh
git clone git@github.com:Park-SM/claude-code-statusline.git "$HOME/claude-code-statusline"
chmod +x "$HOME/claude-code-statusline/"*.sh
```

2) Merge the two entries below into `~/.claude/settings.json`. The statusLine command runs in
a shell, so `$HOME` is expanded.

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

After configuring, **restart Claude Code** to apply it.

## Requirements

- Claude Code CLI
- `jq` (JSON processing)
- `git` (for branch display — if absent or not a git repo, only the branch is hidden)
- a terminal with 256-color + Unicode (█ ░ ⎇) support
