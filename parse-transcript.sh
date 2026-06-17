#!/bin/sh
# Stop hook: parse transcript.jsonl and write cumulative stats per session
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

[ -z "$session_id" ] || [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ] && exit 0

TRACKER_DIR="$HOME/.claude/token-tracker"
mkdir -p "$TRACKER_DIR"

# Parse all assistant usage + count unique promptIds as turns
# Opus 4 pricing: input $15/M, output $75/M, cache_write $18.75/M, cache_read $1.875/M
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
' "$transcript_path" > "$TRACKER_DIR/${session_id}.json" 2>/dev/null

exit 0
