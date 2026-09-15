#!/bin/bash
#
# qa-post-move.sh — Claude Code PostToolUse hook
#
# Fires after mcp__trello__move_card executes. Queries the Ready-for-QA
# list and surfaces the remaining queue to the model via additionalContext
# JSON on stdout — the cue to "pick up the next card" after a successful
# move. For each queued card, also fetches the latest comment whose body
# starts with "## Implementation Notes" or "## Design Notes" and includes a
# short preview
# alongside the card title. Dev's implementation notes are the
# load-bearing input for QA review (disclosed adaptations, deviations,
# files-modified inventory); surfacing them at queue-display time means
# QA picks up the next card with Dev's actual implementation in context
# rather than relying on discipline to fetch comments manually. Cards
# with no notes comment under either heading are flagged with ✗ so the absence
# is visible rather than silent.
#
# Only relevant when a card was just moved OUT of Ready-for-QA. Exits 0
# silently for all other move_card events (e.g., moves between other lists)
# so it never produces noise.
#
# Output channel:
#   STDOUT as a JSON object with hookSpecificOutput.additionalContext.
#   PostToolUse plain stderr is not surfaced to the model on exit 0 —
#   structured JSON is the reliable path.
#
# Matcher in settings.json should be: "mcp__trello__move_card"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes:
#   0 — always. This is observational, not gating.

# Requires-Path: ../board/board.sh
# Board-Actions: move

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names, board calls and the column rule.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
if [[ "$HOOK_ACTION" != "move" ]]; then
  exit 0
fi

board_credentials_present || exit 0

# Column matching by NAME, not hardcoded ID, with the board layer's column
# rule. Portable across projects and boards that share the same column naming.
card_id="$HOOK_CARD_ID"
dest_list_id="$HOOK_DEST_STAGE_ID"

# Only fire when the destination was "Done" or "Now" — the two legitimate
# QA-originated destinations. Silent exit otherwise to avoid noise on
# unrelated moves.
board_stage_get dest_list "$dest_list_id"
dest_list_name=""
if [[ -n "$dest_list" ]]; then
  dest_list_name=$(printf '%s' "$dest_list" | jq -r '.name // empty')
fi
if ! board_column_is "$dest_list_name" done && ! board_column_is "$dest_list_name" now; then
  exit 0
fi

# Resolve the QA column id on this card's board by name. The PreToolUse
# hook had access to the source column; here the card has already moved, so
# look up the board from the card and find the column by name.
board_card_get card "$card_id"
card_board=""
if [[ -n "$card" ]]; then
  card_board=$(printf '%s' "$card" | jq -r '.board_id // empty')
fi
if [[ -z "$card_board" ]]; then
  exit 0
fi
board_stages lists "$card_board"
ready_for_qa_list_id=""
if [[ -n "$lists" ]]; then
  ready_for_qa_list_id=$(printf '%s' "$lists" | jq -r --arg re "$(board_column_regex qa)" \
    '[.[] | select(.name | test($re; "i"))][0].id // empty')
fi
if [[ -z "$ready_for_qa_list_id" ]]; then
  exit 0
fi

board_stage_cards queue "$ready_for_qa_list_id"
queue="${queue:-[]}"
remaining_count=$(echo "$queue" | jq 'length')

# Fetch the latest notes comment per queued card and
# surface a short preview alongside the title. Dev's implementation notes
# are the load-bearing input for QA review — without them, QA reviews
# against Research's plan instead of Dev's actual implementation. Surfacing
# a preview at queue-display time means QA picks up the next card with
# Dev's disclosed adaptations and deviations already in context, rather
# than relying on discipline to remember to fetch comments manually.
#
# Filter is heading-based, and it matches BOTH headings. Dev writes
# "## Implementation Notes"; Design writes "## Design Notes"
# (Designer_Cards.md). Matching only one of them would report every card from
# the other role as having no notes, and a warning that is wrong every time is
# one people stop reading.
#
# The two headings stay distinct on purpose. A Design handoff is not an
# implementation, and collapsing them saves one string and loses a real
# distinction in a system where the roles are deliberately separated.
#
# Heading-based because all role
# instances on this board share one Trello user — author-id filtering
# doesn't work.
# Latest matching comment wins (handles FAIL→Now→rework iterations
# where multiple notes comments accrue across rounds).
fetch_impl_notes_preview() {
  local cid="$1"
  local actions=""
  board_card_notes actions "$cid" 20
  actions="${actions:-[]}"

  local notes_text
  notes_text=$(echo "$actions" | jq -r '
    [.[] | select(.text | test("^## (Implementation|Design) Notes"))] | .[0].text // empty
  ')

  if [[ -z "$notes_text" ]]; then
    printf '%s' "    Notes: ✗ no Implementation Notes or Design Notes comment"
    return
  fi

  # Strip the heading line, take the first ~240 chars of body, collapse
  # whitespace, escape newlines for single-line display.
  local preview
  preview=$(printf '%s' "$notes_text" \
    | awk 'NR==1{next} {print}' \
    | tr '\n' ' ' \
    | tr -s ' ' \
    | sed 's/^ //; s/ $//' \
    | head -c 240)
  printf '    Notes: ✓ %s…' "$preview"
}

if [[ "$remaining_count" == "0" ]]; then
  summary="Ready for QA queue: empty — no cards waiting."
else
  card_suffix="s"
  [[ "$remaining_count" == "1" ]] && card_suffix=""

  lines=""
  while IFS=$'\t' read -r card_id_q card_name_q; do
    [[ -z "$card_id_q" ]] && continue
    preview_line=$(fetch_impl_notes_preview "$card_id_q")
    lines+="  - ${card_name_q}"$'\n'"${preview_line}"$'\n'
  done < <(echo "$queue" | jq -r '.[] | "\(.id)\t\(.title)"')

  summary="Ready for QA queue (${remaining_count} card${card_suffix}):"$'\n'"${lines%$'\n'}"
fi

jq -n --arg ctx "$summary" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
