#!/bin/bash
#
# load-research-coordination.sh — Claude Code SessionStart hook
#
# Emits the raw contents of protocol/Research_Coordination.md via
# hookSpecificOutput.additionalContext so the messaging-bus doc
# is available from turn 1.
#
# Companion loaders (one file per loader, split along semantic seams):
#   - load-research-role.sh     → Research_Role.md
#   - load-research-protocol.sh → protocol/Research_Protocol.md
#   - load-research-cards.sh    → protocol/Research_Cards.md
#   - load-research-hooks.sh        → protocol/Research_Hooks.md
#
# Overflow visibility lives in load-status-digest.sh — keep this
# script dumb. If a doc grows past the harness's additionalContext
# cap, the digest reports it and the fix is to split the source file
# at a new semantic seam, not to slice this loader by byte range.
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/protocol/Research_Coordination.md"

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
