#!/bin/bash
#
# gate-column-scope.sh — Claude Code PreToolUse hook
#
# Enforces Dev_Role.md § Card Management § Column scope: Dev writes only
# to cards currently in "Now". Cards in the QA column hold a Dev handoff
# QA is reviewing; cards in "Done" hold the QA-blessed final state; cards
# in the Research column are Research's. Writing to any of those overwrites
# work that is not Dev's and breaks the handoff chain.
#
# Fires on mcp__trello__update_card_details. Fetches the card's current
# idList, looks up the list name, and denies the write unless the name
# contains the WORD "now" (case-insensitive, on word boundaries).
#
# Deliberately NOT an anchored '^now$'. The board's column label is cosmetic
# and gets relabeled; the role's identity is not. In the Research role an
# anchored '^research and prep$' silently took the whole role offline when
# the column was renamed to "Research" — every description write denied,
# every handoff advance skipped. Word-matching survives a relabel; the
# tighter form only looks safer.
#
# Why match by name rather than ID: the column IDs for the main board are in
# the app CLAUDE.md, but feature worktrees may use different board IDs with
# the same column naming. A name-match works in both cases without requiring
# the ID to be hardcoded here.
#
# Matcher in settings.json: "mcp__trello__update_card_details"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - jq or curl missing
#   - env vars missing
#   - card or list lookup fails (network/auth)
#
# The fail-open posture mirrors the other gate hooks: a transient API blip
# should not block legitimate work. The constraint also lives in prose
# (Dev_Role.md) so the agent can self-enforce when the hook can't.

# Requires-Path: ../board/board.sh
# Board-Actions: update

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names, board calls and the column rule.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0
board_credentials_present || exit 0

hook_read_action
[[ "$HOOK_ACTION" == "update" ]] || exit 0

card_id="$HOOK_CARD_ID"
[[ -z "$card_id" ]] && exit 0

# Fetch the card's current column and name. A failed lookup fails open.
board_card_get card "$card_id"
[[ -n "$card" ]] || exit 0
list_id=$(printf '%s' "$card" | jq -r '.stage_id // empty')
card_name=$(printf '%s' "$card" | jq -r '.title // empty')
[[ -z "$list_id" ]] && exit 0

# Look up the column's name. A failed lookup fails open.
board_stage_get list "$list_id"
[[ -n "$list" ]] || exit 0
list_name=$(printf '%s' "$list" | jq -r '.name // empty')
[[ -z "$list_name" ]] && exit 0

# Allow if the card is in Dev's column.
if board_column_is "$list_name" now; then
  exit 0
fi

# Card is in another column — block.
cat >&2 <<EOF
BLOCKED: card "${card_name}" is in "${list_name}", not in Dev's column.

Cards in the QA column hold a Dev handoff QA is reviewing. Cards in "Done"
hold the QA-blessed final state. Cards in the Research column are Research's
in-progress work. Writing to any of these overwrites work that is not Dev's
and breaks the handoff chain.

Dev_Role.md § Card Management § Column scope: Dev writes only to cards
currently in "Now".

If a card already moved to "Ready for QA" needs an amendment, move it back
to "Now" first — that move is the visible action, and the §5 Definition of
Done check applies to the next move out. Don't write in place to a Ready
for QA card.
EOF
exit 2
