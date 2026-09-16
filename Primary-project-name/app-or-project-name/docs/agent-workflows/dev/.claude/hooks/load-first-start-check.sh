#!/bin/bash
#
# load-first-start-check.sh — Claude Code SessionStart hook
#
# While any {{placeholder}} remains in the walk-up CLAUDE.md files, the board
# config or settings.local.json, setup is not finished and this role cannot
# work. This hook says so at session start, so the session sends the user to
# the orchestrator instead of improvising, whatever the user opens with.
#
# The instruction also lives in CLAUDE.md. Prose alone was skippable: a
# session that starts answering the user's first question never gets to it.
#
# Silent once setup has filled every placeholder, so it costs nothing after
# the first run.
#
# Requires: jq
#
# Exit codes: always 0. Informational only, never blocks a session.

set -uo pipefail

ROLE_DIR="${CLAUDE_PROJECT_DIR:-$(cd -P "$(dirname "$0")/.." && pwd)}"
ROLE_NAME="$(basename "$ROLE_DIR")"

pending=""
for f in \
  "$ROLE_DIR/CLAUDE.md" \
  "$ROLE_DIR/../../CLAUDE.md" \
  "$ROLE_DIR/../../../CLAUDE.md" \
  "$ROLE_DIR/../../../../CLAUDE.md" \
  "$ROLE_DIR/../board/board.conf" \
  "$ROLE_DIR/.claude/settings.local.json"; do
  [ -f "$f" ] || continue
  if grep -q '{{' "$f" 2>/dev/null; then
    count=$(grep -o '{{[A-Z_]*}}' "$f" | sort -u | wc -l | tr -d ' ')
    name=$(cd -P "$(dirname "$f")" 2>/dev/null && pwd)/$(basename "$f")
    pending="${pending}  - ${name}  (${count} unfilled)"$'\n'
  fi
done

[ -n "$pending" ] || exit 0

banner=""
banner+=$'\n'
banner+="================================================================"$'\n'
banner+="  SETUP IS NOT FINISHED. DO NO WORK YET."$'\n'
banner+="================================================================"$'\n'
banner+=$'\n'
banner+="These files still hold placeholders:"$'\n'
banner+="$pending"
banner+=$'\n'
banner+="The ${ROLE_NAME} role cannot work until the orchestrator has run"$'\n'
banner+="first start. Whatever the user opens with:"$'\n'
banner+=$'\n'
banner+="  1. Tell them setup has not been run, in one sentence."$'\n'
banner+="  2. Point them at the orchestrator:"$'\n'
banner+="       cd ../orchestrator && claude"$'\n'
banner+="     and say to tell it they are setting up."$'\n'
banner+="  3. Stop there. Do not plan, do not read handoffs, do not write"$'\n'
banner+="     cards, do not touch the board."$'\n'
banner+=$'\n'
banner+="If the user opens with something else, answer in a sentence or"$'\n'
banner+="two, then say setup comes first."$'\n'
banner+=$'\n'
banner+="If the user asks you to work anyway: say the gates are off and"$'\n'
banner+="the board id is unset, so nothing you did would be enforced or"$'\n'
banner+="land on the right board. Offer to pick up the moment setup is"$'\n'
banner+="done."$'\n'
banner+=$'\n'
banner+="================================================================"$'\n'

printf '%s' "$banner" >&2

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$banner" --arg role "$ROLE_NAME" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    },
    "systemMessage": ("Setup is not finished. Send the user to the orchestrator to run first start. The " + $role + " role does no work until then.")
  }'
fi

exit 0
