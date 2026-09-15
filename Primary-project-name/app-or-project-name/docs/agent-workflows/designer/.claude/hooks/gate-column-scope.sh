#!/bin/bash
#
# gate-column-scope.sh — Claude Code PreToolUse hook
#
# Enforces the DESIGNER's column scope: Design writes to cards in its own
# column, and to cards it raises into Next or Research. Cards in "Now" are
# Dev's in-progress work; cards in QA hold a handoff QA is reviewing; cards
# in "Done" are the QA-blessed final record. Writing to any of those
# overwrites work that is not Design's and breaks the handoff chain.
#
# Fires on mcp__trello__update_card_details. Fetches the card's current
# idList, looks up the list name, and denies the write unless the name
# contains the WORD "design", "next" or "research" (case-insensitive, on
# word boundaries).
#
# Deliberately NOT an anchored match. The board's column label is cosmetic
# and gets relabeled; the role's identity is not. An exact match silently
# takes the role offline when a column is renamed. Word-matching survives a
# relabel; the tighter form only looks safer.
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
# (Designer_Role.md, Designer_Cards.md) so the agent can self-enforce when
# the hook can't.

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

# DESIGNER VERSION. Each role's copy of this gate matches its own column words.
# Do not copy another role's version in here.
#
# Matching by WORD, not label: a column gets relabelled, a role does not.
#
# Design      the Designer's own column.
# Next        cards the Designer raises for the Orchestrator to route. A card
#             cannot carry its required "#idShort title apiId" name until it
#             exists and has an id, so naming it has to be allowed.
# Research    same reason, for work stubbed to Research.
#
# NOT allowed: Now, QA, Done. Those hold Dev's in-progress work, a handoff QA is
# reviewing, and the QA-blessed final record. Descriptions everywhere are
# protected separately by block-description-writes.sh, which is the hook that
# actually guards another role's evidence chain.
if board_column_is "$list_name" design \
  || board_column_is "$list_name" next \
  || board_column_is "$list_name" research; then
  exit 0
fi

# Card is in another column — block.
cat >&2 <<EOF
BLOCKED: card "${card_name}" is in "${list_name}", not in a column Design writes to.

Cards in "Now" are Dev's in-progress work. Cards in QA hold a handoff QA is
reviewing. Cards in "Done" are the QA-blessed final record. Writing to any of
those overwrites work that is not Design's and breaks the handoff chain.

Design writes to its own column, and to cards it raises into Next or Research.

If a card that has already moved on needs an amendment, that is a comment on the
card or a conversation with the role that owns it now, not a write in place.
EOF
exit 2
