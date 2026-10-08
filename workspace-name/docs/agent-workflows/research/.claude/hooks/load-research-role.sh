#!/bin/bash
#
# load-research-role.sh — Claude Code SessionStart hook
#
# Emits the raw contents of Research_Role.md via
# hookSpecificOutput.additionalContext so the Research role doc
# is available from turn 1.
#
# Companion loaders (one file per loader, split along semantic
# seams — identity / methodology / card mechanics / coordination):
#   - load-research-protocol.sh     → protocol/Research_Protocol.md
#   - load-research-cards.sh        → protocol/Research_Cards.md
#   - load-research-hooks.sh        → protocol/Research_Hooks.md
#   - load-research-coordination.sh → protocol/Research_Coordination.md
#
# Overflow visibility lives in load-status-digest.sh (runs last in
# SessionStart, measures every doc loader's real emitted body, prints
# OK or WARN at the bottom of session-start context). Do not add
# size-check smarts here — keep this script dumb.
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

FILE="${CLAUDE_PROJECT_DIR}/Research_Role.md"

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
