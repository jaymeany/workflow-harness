#!/bin/bash
#
# load-qa-role.sh — Claude Code SessionStart hook
#
# Emits the raw contents of QA_Role.md via
# hookSpecificOutput.additionalContext so the QA role doc is available
# from turn 1.
#
# Split rationale: the original single-hook bundle exceeded Claude
# Code's 10,000-char additionalContext cap (documented at
# https://code.claude.com/docs/en/hooks), which caused the harness to
# persist the payload and substitute a ~2KB preview instead of
# injecting the full content. Splitting the startup reads across three
# separate SessionStart hooks keeps each payload under the cap.
#
# Companion hooks:
#   - load-qa-checks.sh        → protocol/QA_Checks.md
#   - load-qa-decisions.sh     → protocol/QA_Decisions.md
#   - load-qa-workflow.sh      → protocol/QA_Workflow.md
#   - load-qa-coordination.sh  → protocol/QA_Coordination.md
#
# The app's CLAUDE.md is NOT loaded here — it's in a sibling tree off
# the walk-up path and must be Read explicitly when working on app code.
#
# Requires: jq
#
# Exit codes:
#   0 — always (informational; never blocks a session from starting)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="${CLAUDE_PROJECT_DIR}/QA_Role.md"

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
