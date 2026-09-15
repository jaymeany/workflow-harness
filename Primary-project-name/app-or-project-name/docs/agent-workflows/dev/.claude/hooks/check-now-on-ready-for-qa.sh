#!/bin/bash
#
# check-now-on-ready-for-qa.sh — Claude Code PostToolUse hook
#
# When a card is moved out of Now with the board's move tool — either to the
# QA column (handoff) or to the Research column (Clarification bounce per
# Dev_Protocol §7) — query the Now column and surface the next card as
# additionalContext so Dev keeps pulling without pausing.
#
# Column resolution is name-based, not ID-based, with the board layer's
# column rule. Hardcoded IDs silently no-op when they rotate (board recreated,
# worktree-specific board, etc.) — name matching survives ID churn.
#
# Matcher in settings.json: the board's move tool.
# Hook event: PostToolUse
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
# Requires-Path: ../board/board.sh
# Board-Actions: move
#
# Exit codes: always 0 (never blocks; informational only)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
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

target_list="$HOOK_DEST_STAGE_ID"
[[ -z "$target_list" ]] && exit 0

if ! board_credentials_present; then
  # Resolve dest name without API; we can't, so report a degraded message.
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": "Card moved. Could not query Now column — TRELLO_API_KEY and TRELLO_API_TOKEN (or TRELLO_TOKEN) must be set in hook env."
    }
  }'
  exit 0
fi

# Resolve the destination column's name and board in one call.
board_stage_get dest_meta "$target_list"
dest_name=""
board_id=""
if [[ -n "$dest_meta" ]]; then
  dest_name=$(printf '%s' "$dest_meta" | jq -r '.name // empty')
  board_id=$(printf '%s' "$dest_meta" | jq -r '.board_id // empty')
fi

[[ -z "$dest_name" || -z "$board_id" ]] && exit 0

if board_column_is "$dest_name" qa; then
  move_label="moved to Ready for QA"
elif board_column_is "$dest_name" research; then
  move_label="bounced to Research and prep"
else
  # Move went somewhere we don't surface from (e.g., Done, Archive).
  exit 0
fi

# Find the Now column on the same board by name.
board_stages lists "$board_id"
now_list_id=""
if [[ -n "$lists" ]]; then
  now_list_id=$(printf '%s' "$lists" | jq -r --arg re "$(board_column_regex now)" \
    '[.[] | select(.name | test($re; "i"))][0].id // empty' 2>/dev/null || echo "")
fi

if [[ -z "$now_list_id" ]]; then
  jq -n --arg label "$move_label" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Card " + $label + ". Could not resolve a list named \"Now\" on this board.")
    }
  }'
  exit 0
fi

# Fetch cards in Now, in board order. Only the first is used.
board_stage_cards response "$now_list_id"

if [[ -z "$response" ]] || ! echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
  jq -n --arg label "$move_label" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Card " + $label + ". Trello API call to Now column failed or returned an unexpected shape.")
    }
  }'
  exit 0
fi

count=$(echo "$response" | jq 'length')

if [[ "$count" == "0" ]]; then
  message="Card ${move_label}. Now is empty — queue drained. Stand by."
else
  next_short=$(echo "$response" | jq -r '.[0].number')
  next_id=$(echo "$response" | jq -r '.[0].id')
  next_name=$(echo "$response" | jq -r '.[0].title')
  message=$(printf "Card %s. NEXT CARD: #%s %s (id: %s). Call %s on this id now. Do NOT pause to ask the user — auto-pickup is the policy." "$move_label" "$next_short" "$next_name" "$next_id" "$BOARD_TOOL_GET_CARD")
fi

hook_emit_context PostToolUse "$message"

exit 0
