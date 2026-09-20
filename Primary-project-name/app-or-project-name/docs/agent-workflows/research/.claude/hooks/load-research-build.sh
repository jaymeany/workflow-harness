#!/bin/bash
#
# load-research-build.sh — Claude Code SessionStart hook
#
# Emits Research_Build.md: what this project is building and where the cards
# come from. Split out of Research_Role.md when that file crossed the
# ~9500-char additionalContext cap — past it, the role boots on a 2KB preview
# of its own identity.
#
# Dumb file loader. Reads the file as-is and emits it in full.

set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0
FILE="${CLAUDE_PROJECT_DIR}/Research_Build.md"
[[ -f "$FILE" ]] || exit 0
jq -n --arg ctx "$(cat "$FILE")" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
