#!/bin/bash
#
# apply-research-complete-label.sh — Claude Code PostToolUse hook
#
# Fires after mcp__trello__add_card_to_list succeeds. Evaluates the submitted
# description against the research-complete criteria and, if it qualifies,
# attaches the board's green "Research complete" label to the newly-created
# card.
#
# This closes a gap in the label-on-save flow: gate-research-complete.sh
# handles label attachment for update_card_details and move_card (PreToolUse
# for gating, inline label attach for saves), but PreToolUse cannot attach
# labels to a card that doesn't exist yet. The label must be applied AFTER
# the create, which is this hook's job.
#
# Matcher in settings.json: "mcp__trello__add_card_to_list"
#
# Research-complete criteria + label-attach behavior live in lib.sh, shared
# with gate-research-complete.sh. Both hooks must agree on what qualifies as
# research-complete; keeping the logic in one file prevents drift between
# create-time and update/move-time evaluation.
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes:
#   0 — always (non-blocking; label-attach is best-effort)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# Shared helpers: evaluate_research_complete, attach_research_complete_label.
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__add_card_to_list" ]]; then
  exit 0
fi

# The submitted description lives on tool_input; the new card id on tool_response.
new_desc=$(echo "$input" | jq -r '.tool_input.description // empty')
card_id=$(echo "$input" | jq -r '.tool_response.id // empty')

if [[ -z "$new_desc" || -z "$card_id" ]]; then
  exit 0
fi

status=$(evaluate_research_complete "$new_desc")
if [[ "$status" != "ok" ]]; then
  # Card doesn't qualify (no marker, blocker tag, or unresolved open question).
  # This is the normal path for research-in-progress cards — not an error.
  exit 0
fi

attach_research_complete_label "$card_id"

# Note: auto-advance is deliberately NOT called here. Cards advance only
# from the update_card_details path in gate-research-complete.sh. Reason:
# the title hook requires every newly-created card to be renamed from a
# "[TBD] <title>" placeholder to the canonical "#<idShort> <title> <id>
# dev" via update_card_details immediately after create. If we advanced
# at create time and PostToolUse on add_card_to_list fired (it's flaky on
# MCP tools), the rename would then hit gate-column-scope on a card now
# in Now and get blocked. Letting the rename's update_card_details be
# the trigger keeps the create + rename sequence safe; the rename also
# qualifies for advance via the description's research-complete state,
# so the workflow still ends with the card in Now.

exit 0
