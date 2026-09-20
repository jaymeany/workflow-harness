#!/bin/bash
#
# load-first-start-check.sh — Claude Code SessionStart hook
#
# While any {{placeholder}} remains in the walk-up CLAUDE.md files, the board
# config or settings.local.json, setup is not finished. This hook says so at
# session start, so the orchestrator leads with FIRST_START.md whatever the
# user opens with.
#
# The instruction also lives in CLAUDE.md. Prose alone was skippable: a
# session that starts answering the user's first question never gets to it.
#
# Silent once setup has filled every placeholder, so it costs nothing after
# the first run.
#
# Requires: jq
# Requires-Path: FIRST_START.md
#
# Exit codes: always 0. Informational only, never blocks a session.

set -uo pipefail

ROLE_DIR="${CLAUDE_PROJECT_DIR:-$(cd -P "$(dirname "$0")/.." && pwd)}"

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
banner+="  SETUP IS NOT FINISHED. THIS IS FIRST START."$'\n'
banner+="================================================================"$'\n'
banner+=$'\n'
banner+="These files still hold placeholders:"$'\n'
banner+="$pending"
banner+=$'\n'
banner+="Do this before anything else, whatever the user opens with:"$'\n'
banner+=$'\n'
banner+="  1. Say setup comes first, in one sentence, before you run"$'\n'
banner+="     anything. The first thing the user sees should be a"$'\n'
banner+="     sentence, not a command."$'\n'
banner+="  2. Read ./FIRST_START.md."$'\n'
banner+="  3. Open the session as it says: they are setting up a"$'\n'
banner+="     software factory with a lot of moving parts, most of"$'\n'
banner+="     them settled once. Nothing is locked in, they can stop"$'\n'
banner+="     any time. Give the 30 to 45 minute range and say it"$'\n'
banner+="     depends on how much you do. Plainly, not as a warning."$'\n'
banner+="  4. Build the TodoWrite list from the values already filled"$'\n'
banner+="     in, and show it before the first question."$'\n'
banner+="  5. Run it with them from the first unfinished step, one"$'\n'
banner+="     step at a time, waiting for each answer."$'\n'
banner+=$'\n'
banner+="Until every placeholder is filled: do not plan work, do not read"$'\n'
banner+="handoffs, do not write cards, do not touch the board. The other"$'\n'
banner+="roles refuse to work until setup is done, and the board gates"$'\n'
banner+="allow everything while the board id is unset."$'\n'
banner+=$'\n'
banner+="If the user opens with something else, answer in a sentence or"$'\n'
banner+="two, then start setup."$'\n'
banner+=$'\n'
banner+="If the user asks to skip setup: say the gates are off and the"$'\n'
banner+="other roles will refuse to work until the placeholders are"$'\n'
banner+="filled, offer to run it whenever they are ready, and do not"$'\n'
banner+="start project work in the meantime."$'\n'
banner+=$'\n'
banner+="================================================================"$'\n'

printf '%s' "$banner" >&2

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$banner" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    },
    "systemMessage": "Setup is not finished. Read FIRST_START.md and run it with the user before anything else."
  }'
fi

exit 0
