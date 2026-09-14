#!/bin/bash
#
# block-description-writes.sh — Claude Code PreToolUse hook
#
# Backstop for QA_Role.md § Card Management § Hard Constraints:
# QA writes review results to comments. The card description belongs to
# Research (it's the evidence chain of what was found, what was decided,
# what's in scope). When QA writes the description field on an existing
# card, the wholesale-replace semantics of update_card_details destroy
# Research's record.
#
# QA review notes go in comments via mcp__trello__add_comment, per the
# §9 template enforced by qa-protocol-compliance.sh.
#
# Tracking-card creation exception: QA creates tracking cards via
# mcp__trello__add_card_to_list, which writes the description at creation
# time. That tool is not gated by this hook — only update_card_details
# is. Creating a tracking card with a description in the create call works
# normally; updating an existing card's description does not.
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
BLOCKED: QA cannot write the card description (cardId: ${card_id:-unknown}).

The card description is Research's evidence chain — research findings,
decisions, scope. update_card_details replaces the description field
wholesale, so any QA-side write to that field destroys Research's record
even if the intent was append.

QA_Role.md § Card Management § Hard Constraints: QA writes review results
to comments. Use mcp__trello__add_comment with the §9 QA Comment template.

Tracking-card exception: when CREATING a tracking card, use
mcp__trello__add_card_to_list with the description set in the create call.
That tool isn't gated by this hook — the description-at-creation path is
the supported way to set a tracking card's description. Once the tracking
card exists, further description edits via update_card_details are denied
the same as any other card.

To proceed:
  - If you're posting a QA review, use mcp__trello__add_comment with the
    §9 template body.
  - If you're creating a tracking card, use mcp__trello__add_card_to_list
    (not update_card_details).
  - If you need to change the card name or labels (not the description),
    re-issue update_card_details without the description field.
EOF
exit 2
