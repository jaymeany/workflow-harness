#!/bin/bash
#
# apply-needs-research-label.sh — Claude Code PreToolUse hook
#
# When Dev moves a card to "Research and prep" (the clarification-back
# flow triggered when Dev finds research insufficient or incorrect),
# apply the blue "Needs research" label to the card. This is the
# board-level visual marker that pairs with the `[Needs Clarification]`
# name tag Dev adds per Dev_Protocol.md §7.
#
# Non-fatal: label lookup or application failures do not block the
# move. If the blue "Needs research" label doesn't exist on the board,
# the hook silently no-ops.
#
# Matcher in settings.json: "mcp__trello__move_card"
# Hook event: PreToolUse
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes: always 0 (non-blocking; informational side-effect only)

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
[[ "$HOOK_ACTION" == "move" ]] || exit 0

board_credentials_present || exit 0

card_id="$HOOK_CARD_ID"
dest_list_id="$HOOK_DEST_STAGE_ID"
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

# Fire only when the destination is Research's column.
board_stage_get dest_list "$dest_list_id"
[[ -n "$dest_list" ]] || exit 0
dest_list_name=$(printf '%s' "$dest_list" | jq -r '.name // empty')
[[ -z "$dest_list_name" ]] && exit 0
board_column_is "$dest_list_name" research || exit 0

# Find the board's "Needs research" label. The adapter finds it by what the
# label means (on Trello, the blue label). No such label: do nothing.
board_card_get card "$card_id"
[[ -n "$card" ]] || exit 0
board_id=$(printf '%s' "$card" | jq -r '.board_id // empty')
[[ -n "$board_id" ]] || exit 0

board_labels labels "$board_id"
board_state_label_pick label_id "$labels" needs_research
[[ -n "$label_id" ]] || exit 0

# Attach to the card. The board ignores a duplicate attach.
board_card_label_add "$card_id" "$label_id"

exit 0
