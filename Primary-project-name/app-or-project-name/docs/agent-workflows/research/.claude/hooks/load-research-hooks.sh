#!/bin/bash
#
# load-research-hooks.sh — Claude Code SessionStart hook
#
# Emits the raw contents of protocol/Research_Hooks.md via
# hookSpecificOutput.additionalContext so the hook-enforced inventory
# is available from turn 1.
#
# Exists because Research_Cards.md crossed the harness's ~10K
# additionalContext cap (digest reported OVERFLOW at 10800 chars).
# The fix per load-status-digest.sh is a semantic split, never a
# byte-range slice inside a loader — the seam chosen was
# card-authoring rules (Research_Cards.md) vs. enforcement machinery
# (this file).
#
# Companion loaders (one file per loader, split along semantic seams):
#   - load-research-role.sh         → Research_Role.md
#   - load-research-protocol.sh     → protocol/Research_Protocol.md
#   - load-research-cards.sh        → protocol/Research_Cards.md
#   - load-research-coordination.sh → protocol/Research_Coordination.md
#
# Overflow visibility lives in load-status-digest.sh — keep this
# script dumb. If a doc grows past the cap, the digest reports it and
# the fix is another semantic split, not slicing this loader.
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/protocol/Research_Hooks.md"

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
