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

# The project board, set during setup. See the walk-up project CLAUDE.md § Trello.
TRELLO_BOARD_ID="{{TRELLO_BOARD_ID}}"
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

WATCH_TAG=\"${WATCH_TAG}\"
BOARD=\"${TRELLO_BOARD_ID}\"
WORD_RE='(^|[^a-z0-9])now([^a-z0-9]|\$)'
TOK=\"\${TRELLO_API_TOKEN:-\$TRELLO_TOKEN}\"
LIST=\"\"
warned=0
seen=\"\"
first=1
while true; do
  if [ -z \"\$LIST\" ]; then
    LIST=\$(curl -sf --max-time 10 -G \"https://api.trello.com/1/boards/\$BOARD/lists\" --data-urlencode \"fields=name\" --data-urlencode \"key=\$TRELLO_API_KEY\" --data-urlencode \"token=\$TOK\" 2>/dev/null | jq -r --arg re \"\$WORD_RE\" '[.[] | select(.name | test(\$re; \"i\"))][0].id // empty' 2>/dev/null) || LIST=\"\"
    if [ -z \"\$LIST\" ]; then
      if [ \"\$warned\" -eq 0 ]; then
        echo \"TRELLO watcher: no column found on board \$BOARD yet, or Trello did not answer. Retrying every 20s.\"
        warned=1
      fi
      sleep 20
      continue
    fi
  fi
  out=\$(curl -sf --max-time 10 -G \"https://api.trello.com/1/lists/\$LIST/cards\" --data-urlencode \"fields=idShort,name\" --data-urlencode \"key=\$TRELLO_API_KEY\" --data-urlencode \"token=\$TOK\" 2>/dev/null) || out=\"\"
  if [ -n \"\$out\" ]; then
    if lines=\$(printf '%s' \"\$out\" | jq -r '.[] | (.idShort|tostring) as \$n | (if (.name|startswith(\"#\"+\$n+\" \")) then .name else \"#\"+\$n+\" \"+.name end) as \$t | .id + \" \" + \$t' 2>/dev/null); then
      cur=\"\"
      while IFS= read -r line; do
        [ -n \"\$line\" ] || continue
        id=\"\${line%% *}\"
        cur=\"\$cur|\$id|\"
        case \"\$seen\" in *\"|\$id|\"*) continue ;; esac
        if [ \"\$first\" -eq 1 ]; then
          echo \"TRELLO in-column at boot: \${line#* }\"
        else
          echo \"TRELLO card arrival: \${line#* } (detected \$(date -u +%H:%M:%SZ))\"
        fi
      done <<< \"\$lines\"
      seen=\"\$cur\"
      first=0
    fi
  fi
  sleep 20
done

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
