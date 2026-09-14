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

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__move_card" ]]; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
dest_list_id=$(echo "$input" | jq -r '.tool_input.listId // empty')
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

# Resolve the destination list's name; fire only when it contains "research"
# (case-insensitive substring match). Name-based matching is robust to list
# ID rotation across boards and worktrees — hardcoded IDs silently no-op
# when they go stale. `--fail` makes curl exit non-zero on HTTP 4xx/5xx so
# the `|| echo` fallback engages instead of feeding error bodies into jq.
dest_list=$(curl -sf --max-time 5 "https://api.trello.com/1/lists/${dest_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
dest_list_name=$(echo "$dest_list" | jq -r '.name // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')
[[ -z "$dest_list_name" ]] && exit 0
case "$dest_list_name" in
  *research*) ;;
  *) exit 0 ;;
esac

# Look up the board's blue "Needs research" label.
#
# Matched by COLOR ONLY. This board's blue label is unnamed, so the previous
# `and (.name | ascii_downcase == "needs research")` clause matched nothing and
# every Dev bounce-to-Research silently attached no label at all — the miss
# path below is a bare `exit 0`, so nothing surfaced. Label semantics here are
# carried by the color, not the name.
board_id=$(curl -sf --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idBoard&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null | jq -r '.idBoard // empty' 2>/dev/null || echo "")
if [[ -z "$board_id" ]]; then
  exit 0
fi

labels=$(curl -sf --max-time 5 "https://api.trello.com/1/boards/${board_id}/labels?key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '[]')
label_id=$(printf '%s' "$labels" | jq -r '.[] | select(.color=="blue") | .id' 2>/dev/null | head -n1 || echo "")

if [[ -z "$label_id" ]]; then
  exit 0
fi

# Attach to the card. Idempotent — Trello silently ignores duplicates.
curl -s --max-time 5 -X POST \
  "https://api.trello.com/1/cards/${card_id}/idLabels?value=${label_id}&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" \
  >/dev/null 2>&1 || true

exit 0
