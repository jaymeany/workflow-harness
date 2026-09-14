#!/bin/bash
#
# block-description-writes.sh — Claude Code PreToolUse hook
#
# Backstop for Dev_Role.md § Card Management § Hard Constraints:
# Dev writes only to comments. The card description belongs to Research
# (it's the evidence chain of what was found, what was decided, what's in
# scope). When Dev writes the description field, the wholesale-replace
# semantics of update_card_details destroy Research's record.
#
# Implementation Notes go in comments via mcp__trello__add_comment, per
# Dev_Protocol.md §6. The card description is never written by Dev.
#
# This hook denies any update_card_details call where tool_input.description
# is set. Name-only or label-only updates pass through unaffected.
#
# Matcher in settings.json: "mcp__trello__update_card_details"
#
# Requires: jq
#
# Exit codes:
#   0 — allow (description not in payload)
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - jq missing
#
# This hook does not require Trello API access — it operates on the tool
# input alone. Does not fetch the card; the rule is "no description field
# in the update," not "no description content change."

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__update_card_details" ]]; then
  exit 0
fi

# If tool_input doesn't include a description field, this is a name/label-only
# update. Pass through.
has_desc=$(echo "$input" | jq -r '.tool_input | has("description")')
if [[ "$has_desc" != "true" ]]; then
  exit 0
fi

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')

cat >&2 <<EOF
BLOCKED: Dev cannot write the card description (cardId: ${card_id:-unknown}).

The card description is Research's evidence chain — research findings,
decisions, scope. update_card_details replaces the description field
wholesale, so any Dev-side write to that field destroys Research's record
even if the intent was append.

Dev_Role.md § Card Management § Hard Constraints: Dev writes only to
comments. Implementation Notes go in comments via mcp__trello__add_comment,
per Dev_Protocol.md §6.

To proceed:
  - If you're adding Implementation Notes, use mcp__trello__add_comment
    with the §6 template body.
  - If you need to change the card name or labels (not the description),
    re-issue update_card_details without the description field.
  - If the card description is genuinely wrong and needs Research's
    correction, raise it with the user — do not write the description
    yourself.
EOF
exit 2
