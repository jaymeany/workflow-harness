#!/bin/bash
#
# gate-column-scope.sh — Claude Code PreToolUse hook
#
# Enforces Research_Role.md § Card Management § Hard Constraints #1:
# Research writes only to cards currently in Research's column. A card in
# any other column is immutable from Research's perspective — no description
# edits, no label changes, no renames.
#
# Fires on mcp__trello__update_card_details. Fetches the card's current
# idList, looks up the list name, and denies the write if the list isn't
# the Research column. List name is matched via is_research_column (lib.sh):
# the word "research" anywhere in the name, on word boundaries — so a board
# relabel from "Research and prep" to "Research" doesn't take the role
# offline. Same naming-based approach gate-research-complete.sh uses for the
# "Now" column gate, so the hook works across the main board and
# feature-worktree boards that share column naming.
#
# Why match by name rather than ID: the Research column ID for the main
# board is in the app CLAUDE.md, but feature worktrees may use different
# board IDs with the same column naming. A name-match works in both cases
# without requiring the ID to be hardcoded here.
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
# (Research_Role.md) so the agent can self-enforce when the hook
# can't.

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

# Fetch the card's current column, name and description. A failed lookup fails open.
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

# Allow if the card is in Research's column.
if board_column_is "$list_name" research; then
  exit 0
fi

# Now-column addendum exception: Research MAY append
# a clearly-marked addendum to a card in the "Now" column so Dev reads
# corrections IN CONTEXT at pickup instead of being interrupted on the bus.
# Strictly bounded: description-only write, strict append (current description
# preserved verbatim as a prefix), and the appended text must carry the
# "## Research Addendum" header. Everything else stays blocked.
if board_column_is "$list_name" now; then
  new_desc="$HOOK_DESCRIPTION"
  other_fields="$HOOK_OTHER_INPUT_KEYS"
  if [[ -n "$new_desc" && "$other_fields" == "0" ]]; then
    cur_desc=$(printf '%s' "$card" | jq -r '.description // empty')
    if [[ -n "$cur_desc" && "$new_desc" == "$cur_desc"* ]]; then
      appended="${new_desc#"$cur_desc"}"
      if [[ "$appended" == *"## Research Addendum"* ]]; then
        exit 0
      fi
    fi
  fi
  cat >&2 <<EOF
BLOCKED: card "${card_name}" is in "${list_name}" (Dev's column). The ONLY
write Research may make here is a marked append-only addendum:
  - description-only (no name/label/other fields in the same call)
  - new description = current description + appended text (verbatim prefix)
  - appended text contains a "## Research Addendum" header
This lets Dev read corrections in context at card pickup without the
description ever being rewritten under them.
EOF
  exit 2
fi

# Card is in another column — block.
cat >&2 <<EOF
BLOCKED: card "${card_name}" is in "${list_name}", which is not Research's column.

Research_Role.md § Card Management § Hard Constraints #1: Research
writes only to cards currently in its own column (plus marked append-only
addenda to "Now" cards — see the Now-column exception in this hook). A card
in any other column is immutable from Research's perspective.

If clarification is needed on a card outside the Research column, route the
question through the user — do not write to the card.
EOF
exit 2
