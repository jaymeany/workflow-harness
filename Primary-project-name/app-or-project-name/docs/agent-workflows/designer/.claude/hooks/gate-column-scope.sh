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

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__update_card_details" ]]; then
  exit 0
fi

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
[[ -z "$card_id" ]] && exit 0

# Fetch card's current list and name.
card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idList,name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
list_id=$(echo "$card" | jq -r '.idList // empty')
card_name=$(echo "$card" | jq -r '.name // empty')

# Card lookup failed — fail open (don't block on transient API issues).
[[ -z "$list_id" ]] && exit 0

# Look up the list's name.
list=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
list_name=$(echo "$list" | jq -r '.name // empty')

# List lookup failed — fail open.
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
if echo "$list_name" | grep -qiE '(^|[^[:alnum:]])(design|next|research)([^[:alnum:]]|$)'; then
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
