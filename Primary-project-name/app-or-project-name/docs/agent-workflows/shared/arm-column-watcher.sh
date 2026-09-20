#!/bin/bash
#
# arm-column-watcher.sh — Claude Code SessionStart hook (roles with a column)
#
# ONE copy, shared by every role with a column, the way board/board.sh is.
# The role is $CLAUDE_PROJECT_DIR's basename and its column follows from that,
# so the same file serves Research, Designer, Dev and QA. The Orchestrator has
# no column and does not run it.
#
# WHAT IT EMITS
#
#   1. The column rule. Which column belongs to this role, which board, and
#      never to touch another one. Always emitted. That is orientation, not a
#      feature, and it is small.
#
#   2. The column watcher, depending on BOARD_WATCHER in preferences.conf.
#      The watcher is a doorbell: a persistent Monitor that polls this role's
#      column read-only and wakes the agent when a card arrives, instead of
#      spending a turn on every poll.
#
# THIS HOOK MAKES NO BOARD CALL. It emits text. The watcher's own poll runs
# inside the Monitor shell once the agent arms it. Card OPERATIONS always go
# through the board's MCP tools; deny-direct-trello-api.sh gates Bash.
#
# NAMING
#
# This was five files called load-<role>-trello-catchup.sh. Every part of that
# was wrong. It catches up on nothing; it arms a watcher. It is not Trello
# specific; it calls board_column_regex and board_watch_command, and the
# adapter decides what those mean. And the load- prefix put it in the
# namespace load-status-digest.sh globs for protocol docs, so the digest
# measured it as though it were one and reported a doc count that was wrong.
# The name was the bug.
#
# WHY IT IS NOT TRELLO SPECIFIC
#
# Credentials are checked with board_credentials_present, and the product is
# named with BOARD_PRODUCT, both from the adapter. Swap the adapter and this
# hook is still correct without being edited.
#
# WATCH_TAG carries the project slug. pgrep -f matches across the whole
# machine, so an unqualified tag would detect another project's watcher and
# tell this session not to arm, silently leaving this role with none.
#
# Requires: jq, pgrep
# Requires-Path: ../board/board.sh
#
# Fail-open: missing jq exits silent; missing credentials emits the column
# rule with a cannot-arm note.
#
# Exit codes: always 0. Informational only, never blocks a session.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0

# The board layer: the board id, the column rule and the watcher loop.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

# ---------------------------------------------------------------------------
# Which column belongs to this role
#
# Derived from the session cwd, never hardcoded. A role with no column here
# has no watcher to arm, which is how the Orchestrator falls out.
# ---------------------------------------------------------------------------
ROLE="$(basename "$CLAUDE_PROJECT_DIR")"
case "$ROLE" in
  research) COLUMN="research" ;;
  designer) COLUMN="design" ;;
  dev)      COLUMN="now" ;;
  qa)       COLUMN="qa" ;;
  *)        exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Preference
# ---------------------------------------------------------------------------
BOARD_WATCHER="off"
_prefs="$(dirname "${BASH_SOURCE[0]}")/preferences.conf"
if [ -f "$_prefs" ]; then
  # shellcheck disable=SC1090
  . "$_prefs"
fi
case "${BOARD_WATCHER:-}" in
  auto|ask|off) ;;
  *) BOARD_WATCHER="off" ;;
esac

PRODUCT="${BOARD_PRODUCT:-the board}"
WATCH_TAG="board-column-watch-${ROLE}-{{PROJECT_SLUG}}"

# ---------------------------------------------------------------------------
# 1. The column rule. Always.
# ---------------------------------------------------------------------------
column_rule="Board: the {{PROJECT_NAME}} board, id ${BOARD_ID}, the only board this
project touches. Never read, write or move a card on any other board.

${PRODUCT} column for this role: the board's ${COLUMN} column, whichever list
name contains the word \"${COLUMN}\". Do not treat any exact label as
canonical; match on the word, not the full string.

Use /check-trello on demand to read the column. Do NOT start a polling loop of
your own."

# ---------------------------------------------------------------------------
# 2. The watcher, if it is wanted.
# ---------------------------------------------------------------------------
watch_block=""

if [ "$BOARD_WATCHER" != "off" ]; then
  if ! board_credentials_present; then
    watch_block="COLUMN WATCHER: ${PRODUCT} credentials are not set, so it cannot be armed this boot (fail-open). The column is still reachable with /check-trello."
  else
    existing=""
    if command -v pgrep >/dev/null 2>&1; then
      existing=$(pgrep -f "$WATCH_TAG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
    fi
    if [ -n "$existing" ]; then
      precheck="!! EXISTING WATCHER(S) DETECTED: PID(s) ${existing}. Fresh from /clear, the
survivor is still wired to this session; keep it, arm nothing. Kill-then-arm
only if arrivals demonstrably don't land (verify with 'pgrep -f ${WATCH_TAG}').
Never run two: duplicates double-fire every arrival."
    else
      precheck="No existing watcher detected (pgrep clean). Safe to arm."
    fi

    if [ "$BOARD_WATCHER" = "ask" ]; then
      opening="THE COLUMN WATCHER IS AVAILABLE, AND IT IS THE USER'S CALL THIS SESSION.

Tell the user, in one sentence, that you can watch the ${COLUMN} column and
wake when a card arrives, and ask whether to arm it. Do NOT arm it until they
say yes. If they say no, or say nothing about it, carry on without it and do
not raise it again this session."
    else
      opening="ARM THE COLUMN WATCHER. One Monitor, this session."
    fi

    watch_block="${opening}

It emits one event per card ARRIVAL in this role's column; on arming it emits
the column's CURRENT contents, so the first events replace a manual column
check. The board itself is the persistent queue: arrivals while no session was
running are still in the column when it arms.

WATCHER PRE-CHECK (hook-detected at session start):
${precheck}

Call the Monitor tool with persistent: true, timeout_ms: 300000 (the schema
requires the field; it is ignored while persistent), description \"card
arrivals in the {{PROJECT_NAME}} ${COLUMN} column\", and this command:

$(board_watch_command "$WATCH_TAG" "$BOARD_ID" "$(board_column_regex "$COLUMN")")

Discipline notes, do not 'simplify' these:
- zsh-safe by construction: no globs anywhere.
- The watcher finds its column on its first successful poll. Until then it
  prints one notice and retries.
- seen-state is REBUILT from the column on every successful poll, so a card
  that leaves and comes back RE-FIRES (a bounce-back is a real arrival).
- seen only updates when the response parses, so a failed poll can never clear
  state and replay the whole column as fake arrivals.
- 20s poll is 3 read-only API calls a minute.
- The poll is a read-only list read inside the Monitor shell, sanctioned infra
  read. Card OPERATIONS still go through the board's MCP tools ONLY; the Bash
  gate on the board API stands.
- WATCH_TAG carries the project slug so the pre-check cannot false-match
  another project's watcher. Do not shorten it.
- Turn this off, or make it ask first, with BOARD_WATCHER in
  agent-workflows/shared/preferences.conf."
  fi
fi

if [ -n "$watch_block" ]; then
  ctx="${column_rule}

${watch_block}"
else
  ctx="$column_rule"
fi

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
