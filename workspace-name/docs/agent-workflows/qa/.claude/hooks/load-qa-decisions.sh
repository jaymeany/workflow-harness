#!/bin/bash
#
# load-qa-decisions.sh — Claude Code SessionStart hook
#
# Emits the raw contents of protocol/QA_Decisions.md via
# hookSpecificOutput.additionalContext so the decision matrix and §9
# comment template are in context from turn 1.
#
# Dumb file loader: reads the file as-is, emits in full. Does not
# parse the doc or know its structure. Edit protocol/QA_Decisions.md
# however you want — add sections, reorder, rewrite — this hook keeps
# working as long as the file stays under Claude Code's ~10K-char
# additionalContext cap. load-status-digest.sh surfaces overflow at
# session start. When a doc grows past the cap, split it into a new
# semantic file and add another loader; do not slice this loader by
# byte ranges.
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/protocol/QA_Decisions.md"

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
