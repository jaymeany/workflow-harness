#!/bin/bash
#
# load-orchestrator-cards.sh — Claude Code SessionStart hook
#
# Emits the raw contents of protocol/Orchestrator_Cards.md via hookSpecificOutput.additionalContext so
# card mechanics and routing is in context from turn 1.
#
# Dumb file loader: reads the file as-is, emits in full. Edit protocol/Orchestrator_Cards.md however you
# want; this hook keeps working as long as the file stays under Claude Code's
# ~10K-char additionalContext cap. load-status-digest.sh surfaces overflow at
# session start. When a doc grows past the cap, split it into a new semantic
# file and add another loader; do not slice this loader by byte ranges.
#
# Requires: jq
# Exit codes: 0 always (informational; never blocks a session from starting)

set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0
FILE="${CLAUDE_PROJECT_DIR}/protocol/Orchestrator_Cards.md"
[[ -f "$FILE" ]] || exit 0
content=$(tr -d '\001-\010\013\014\016-\037' < "$FILE")
jq -n --arg ctx "$content" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
