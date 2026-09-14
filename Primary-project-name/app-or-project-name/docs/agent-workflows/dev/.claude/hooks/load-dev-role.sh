#!/bin/bash
#
# load-dev-role.sh — Claude Code SessionStart hook
#
# Emits the raw contents of Dev_Role.md via
# hookSpecificOutput.additionalContext so the Dev role briefing is
# available from turn 1.
#
# Dumb file loader: reads the file as-is, emits in full. Does not
# parse the doc or know its structure. Edit Dev_Role.md however
# you want; this hook keeps working as long as the file stays under
# Claude Code's ~10K-char additionalContext cap. load-status-digest.sh
# surfaces overflow at session start.
#
# The app's CLAUDE.md is NOT loaded here — Claude Code auto-loads it
# via the directory hierarchy mechanism (surfaced in the claudeMd
# context block at session start).
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/Dev_Role.md"

if [[ ! -f "$FILE" ]]; then
  exit 0
fi

# Strip non-printable control chars (keep TAB=0x09, LF=0x0A, CR=0x0D)
# to avoid malformed JSON from stray VT/FF/etc. in lifted content.
content=$(tr -d '\001-\010\013\014\016-\037' < "$FILE")

jq -n --arg ctx "$content" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
