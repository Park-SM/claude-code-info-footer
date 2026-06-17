#!/bin/sh
# Claude Code statusLine — pastel 3-line dashboard (+ git branch)
# stdin: JSON session payload from Claude Code
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir=$(basename "$cwd")
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Context usage %. used_percentage is null before the first API call / right after
# /compact, so fall back to computing it from current_usage tokens, then to 0.
used_pct=$(echo "$input" | jq -r '
  if (.context_window.used_percentage != null)
  then .context_window.used_percentage
  else
    (.context_window.current_usage // {}) as $u
    | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $t
    | (.context_window.context_window_size // 200000) as $sz
    | (if ($sz > 0) then ($t / $sz * 100) else 0 end)
  end
')

# Current git branch (empty when cwd is not a git repo)
# symbolic-ref works even on an unborn branch (repo with no commits yet);
# fall back to the short commit hash when HEAD is detached.
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
fi

# Pastel palette (256-color) — all unique
RST="\033[0m"
DIM="\033[2m"
P_LABEL="\033[38;5;253m"    # cream         — labels
P_MODEL="\033[38;5;183m"    # lavender      — model
P_PROJECT="\033[38;5;158m"  # mint          — project
P_BRANCH="\033[38;5;180m"   # warm tan      — git branch
P_CACHE="\033[38;5;111m"    # sky blue      — cache
P_COST="\033[38;5;218m"     # pink          — cost
P_INOUT="\033[38;5;152m"    # teal          — in/out
P_TURN="\033[38;5;216m"     # peach         — turn
G_GOOD="\033[38;5;114m"     # pastel green
G_NORMAL="\033[38;5;117m"   # pastel blue
G_WARNING="\033[38;5;222m"  # pastel yellow
G_DANGER="\033[38;5;210m"   # pastel red

# Label padding: name is padded to 8 so values start at the same column
# with a consistent gap after the longest label ("memory" → 2 spaces).
PAD="%-8s"

# ── Line 1: env ── working environment: model | project (dir) [⎇ branch]
label1="◈ $(printf "$PAD" "env")"
line1="${P_LABEL}${label1}${RST}${P_MODEL}${model}${RST} ${DIM}|${RST} ${P_PROJECT}⧉ ${dir}${RST}"
if [ -n "$branch" ]; then
  line1="${line1} ${DIM}|${RST} ${P_BRANCH}⎇ ${branch}${RST}"
fi

# ── Line 2: memory ── context window gauge + cache hit rate
label2="◐ $(printf "$PAD" "memory")"
line2="${P_LABEL}${label2}${RST}"

# Always render the gauge; defaults to 0% early in the session when no usage yet.
used_int=$(printf "%.0f" "${used_pct:-0}")
[ "$used_int" -lt 0 ] && used_int=0
[ "$used_int" -gt 100 ] && used_int=100
filled=$((used_int / 5))
empty=$((20 - filled))
bar=""
i=0; while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i + 1)); done
i=0; while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i + 1)); done

if [ "$used_int" -ge 80 ]; then
  gc="$G_DANGER"; label="DANGER"
elif [ "$used_int" -ge 50 ]; then
  gc="$G_WARNING"; label="WARNING"
elif [ "$used_int" -ge 30 ]; then
  gc="$G_NORMAL"; label="NORMAL"
else
  gc="$G_GOOD"; label="GOOD"
fi
line2="${line2}${gc}[${bar}] ${used_int}% ${label}${RST}"

last_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
last_cw=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
last_cr=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
last_total=$((last_in + last_cw + last_cr))
if [ "$last_total" -gt 0 ]; then
  cache_pct=$(awk "BEGIN {printf \"%.0f\", $last_cr / $last_total * 100}")
  line2="${line2} ${DIM}|${RST} ${P_CACHE}cache:${cache_pct}%${RST}"
fi

# ── Line 3: usage ── cumulative cost / tokens / turns (per session)
label3="◷ $(printf "$PAD" "usage")"
TRACKER_DIR="$HOME/.claude/token-tracker"
TRACKER_FILE="$TRACKER_DIR/${session_id}.json"

# Fallback: if tracker is missing or stale, parse transcript directly
if [ -n "$session_id" ]; then
  project_key=$(echo "$cwd" | tr '/' '-')
  TRANSCRIPT="$HOME/.claude/projects/${project_key}/${session_id}.jsonl"

  if [ -f "$TRANSCRIPT" ]; then
    need_parse=false
    if [ ! -f "$TRACKER_FILE" ]; then
      need_parse=true
    elif [ "$TRANSCRIPT" -nt "$TRACKER_FILE" ]; then
      need_parse=true
    fi

    if [ "$need_parse" = true ]; then
      mkdir -p "$TRACKER_DIR"
      jq -s '
        [.[] | select(.type == "assistant" and .message.usage != null) | .message.usage] as $u |
        ([.[] | select(.promptId != null) | .promptId] | unique | length) as $turns |
        ($u | map(.input_tokens // 0) | add // 0) as $in |
        ($u | map(.output_tokens // 0) | add // 0) as $out |
        ($u | map(.cache_creation_input_tokens // 0) | add // 0) as $cw |
        ($u | map(.cache_read_input_tokens // 0) | add // 0) as $cr |
        {
          input_tokens: $in,
          output_tokens: $out,
          cache_creation_tokens: $cw,
          cache_read_tokens: $cr,
          turns: $turns,
          cost_usd: (($in * 15 + $cw * 18.75 + $cr * 1.875 + $out * 75) / 1000000)
        }
      ' "$TRANSCRIPT" > "$TRACKER_FILE" 2>/dev/null
    fi
  fi
fi

if [ -n "$session_id" ] && [ -f "$TRACKER_FILE" ]; then
  tracker=$(cat "$TRACKER_FILE")
  t_in=$(echo "$tracker" | jq -r '.input_tokens // 0')
  t_out=$(echo "$tracker" | jq -r '.output_tokens // 0')
  t_cw=$(echo "$tracker" | jq -r '.cache_creation_tokens // 0')
  t_cr=$(echo "$tracker" | jq -r '.cache_read_tokens // 0')
  t_turns=$(echo "$tracker" | jq -r '.turns // 0')
  t_cost=$(echo "$tracker" | jq -r '.cost_usd // 0')

  total_in=$((t_in + t_cw + t_cr))
  total_in_k=$(awk "BEGIN {printf \"%.1f\", $total_in / 1000}")
  total_out_k=$(awk "BEGIN {printf \"%.1f\", $t_out / 1000}")
  cost_fmt=$(awk "BEGIN {printf \"%.2f\", $t_cost}")
else
  cost_fmt="-"
  total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
  total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
  total_in_k=$(awk "BEGIN {printf \"%.1f\", $total_input / 1000}")
  total_out_k=$(awk "BEGIN {printf \"%.1f\", $total_output / 1000}")
fi

# Plan detection: rate_limits is only sent to Claude.ai (Pro/Max) subscribers,
# so its presence means a subscription plan; absence means an API plan.
five_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

line3="${P_LABEL}${label3}${RST}${P_COST}\$${cost_fmt}${RST}"
if [ -n "$five_used" ] || [ -n "$week_used" ]; then
  # ── Subscription plan: show remaining usage of each rate-limit window ──
  if [ -n "$five_used" ]; then
    five_left=$(awk "BEGIN {printf \"%.0f\", 100 - $five_used}")
    line3="${line3} ${DIM}|${RST} ${P_INOUT}session ${five_left}% left${RST}"
  fi
  if [ -n "$week_used" ]; then
    week_left=$(awk "BEGIN {printf \"%.0f\", 100 - $week_used}")
    line3="${line3} ${DIM}|${RST} ${P_TURN}weekly ${week_left}% left${RST}"
  fi
  line3="${line3} ${DIM}|${RST} ${P_CACHE}turn:${t_turns:-0}${RST}"
else
  # ── API plan (or before first response): show input/output tokens ──
  line3="${line3} ${DIM}|${RST} ${P_INOUT}in:${total_in_k}k out:${total_out_k}k${RST} ${DIM}|${RST} ${P_TURN}turn:${t_turns:-0}${RST}"
fi

# Output order: env (line1) → usage (line3) → memory (line2)
printf "%b\n%b\n%b" "$line1" "$line3" "$line2"
