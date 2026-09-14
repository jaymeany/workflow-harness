#!/bin/bash
#
# load-dev-cards.sh — Claude Code SessionStart hook
#
# Emits the raw contents of Dev_Cards.md (Definition of Done, Card
# Update Format, Clarification Protocol, Partial Completion) via
# hookSpecificOutput.additionalContext so the doc is in context from
# turn 1.
#
# Dumb file loader: reads the file as-is, emits in full. Does not
# parse the doc or know its structure. Edit Dev_Cards.md however
# you want; this hook keeps working as long as the file stays under
# Claude Code's ~10K-char additionalContext cap. load-status-digest.sh
# surfaces overflow at session start.
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/protocol/Dev_Cards.md"

if [[ ! -f "$FILE" ]]; then
  exit 0
fi

content=$(tr -d '\001-\010\013\014\016-\037' < "$FILE")

jq -n --arg ctx "$content" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
