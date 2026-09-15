#!/bin/bash
#
# load-dev-trello-catchup.sh — Claude Code SessionStart hook
#
# Emits the role's Trello column rule AND the instruction to arm the TRELLO
# COLUMN WATCHER. The watcher is a persistent Monitor polling this role's
# column read-only. It is a doorbell: the model is woken only when a card
# arrives, instead of spending a full turn on every poll.
#
# This hook makes no Trello call. The watcher finds the column's list id on its
# own first poll, by the WORD "now" in the list name, never an exact label.
# Labels get renamed; an exact match silently takes the role offline.
#
# The watcher's curl is a read-only list poll inside the Monitor shell —
# sanctioned infra read. Card OPERATIONS still go through mcp__trello__*
# only; deny-direct-trello-api.sh gates Bash.
#
# WATCH_TAG carries the project slug. pgrep -f matches across the whole
# machine, so an unqualified tag would detect another project's watcher and
# tell this session not to arm, silently leaving this role with no watcher.
#
# Requires: jq, curl, pgrep
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required
#
# Fail-open: missing jq → exit 0 silent; missing curl/creds → column rule
# emitted with a cannot-arm status line.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# The board layer: the board id, the column rule and the watcher loop.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

# The project board, set during setup in board/board.conf.
TRELLO_BOARD_ID="${BOARD_ID}"
TRELLO_TOK="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
WATCH_TAG="trello-list-watch-dev-{{PROJECT_SLUG}}"

column_rule="Board: the {{PROJECT_NAME}} board, id ${TRELLO_BOARD_ID}, the only board this
project touches. Never read, write or move a card on any other board.

When you arm the watcher, tell the user which board you are watching, by name
and id. If the project CLAUDE.md names more than one board, ask the user which
one first.

Trello column for this role: the board's dev column, whichever list
name contains the word \"now\". Do not treat any exact label as canonical;
match on the word, not the full string.

Use /check-trello on demand for card work. Do NOT start a polling loop —
the column watcher below is the wake signal for new cards."

trello_watch_block="TRELLO COLUMN WATCHER: TRELLO_API_KEY / token not set — cannot arm this boot (fail-open). Column state still reachable via /check-trello."
if [[ -n "${TRELLO_API_KEY:-}" && -n "$TRELLO_TOK" ]] && command -v curl >/dev/null 2>&1; then
  existing_trello_watcher=$(pgrep -f "$WATCH_TAG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
  if [[ -n "$existing_trello_watcher" ]]; then
    trello_precheck="!! EXISTING TRELLO WATCHER(S) DETECTED: PID(s) ${existing_trello_watcher} — fresh from /clear, the survivor is still wired to this
session; keep it, arm nothing. Kill-then-arm only if arrivals demonstrably
don't land (verify with 'pgrep -f ${WATCH_TAG}'). Never run two:
duplicates double-fire every arrival."
  else
    trello_precheck="No existing Trello watcher detected (pgrep clean) — arm fresh below."
  fi
  trello_watch_block="ARM THE TRELLO COLUMN WATCHER — one Monitor, every session. It emits one event per card ARRIVAL in this role's
column; on arming it emits the column's CURRENT contents, so the first events
replace a manual column check. The board itself is the persistent queue —
arrivals while no session was running are still in the column when it arms.

TRELLO WATCHER PRE-CHECK (hook-detected at session start):
${trello_precheck}

Call the Monitor tool with persistent: true, timeout_ms: 300000 (the schema
requires the field; it is ignored while persistent), description \"card
arrivals in {{PROJECT_NAME}} Now column\", and this command:

$(board_watch_command "$WATCH_TAG" "$TRELLO_BOARD_ID" "$(board_column_regex now)")

Discipline notes — do not 'simplify' these:
- zsh-safe by construction: no globs anywhere.
- The watcher finds its column on its first successful poll. Until then it
  prints one notice and retries.
- seen-state is REBUILT from the column on every successful poll, so a card
  that leaves and comes back RE-FIRES (a bounce-back is a real arrival).
- seen only updates when jq parses the response — a failed poll can never
  clear state and replay the whole column as fake arrivals.
- 20s poll = 3 read-only API calls/min against Trello's 300-per-10s limit.
- The curl is a read-only list poll inside the Monitor shell — sanctioned
  infra read. Card OPERATIONS still go through mcp__trello__* ONLY; the Bash
  gate on api.trello.com stands.
- WATCH_TAG carries the project slug so the pre-check pgrep cannot
  false-match another project's watcher. Do not shorten it."
fi

ctx="${column_rule}

${trello_watch_block}"

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
