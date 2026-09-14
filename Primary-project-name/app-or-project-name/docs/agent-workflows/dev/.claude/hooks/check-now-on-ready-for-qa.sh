#!/bin/bash
#
# check-now-on-ready-for-qa.sh — Claude Code PostToolUse hook
#
# When a card is moved out of Now via mcp__trello__move_card — either to
# "Ready for QA" (handoff) or to "Research and prep" (Clarification bounce
# per Dev_Protocol §7) — query the Now column and surface the next card as
# additionalContext so Dev keeps pulling without pausing.
#
# List resolution is name-based, not ID-based: the destination list's name
# is fetched once and matched on case-insensitive substrings ("qa",
# "research"); the Now list ID is resolved at runtime by listing the
# moved card's board and matching "now". Hardcoded IDs silently no-op when
# they rotate (board recreated, worktree-specific board, etc.) — name
# matching survives ID churn.
#
# Matcher in settings.json should be: "mcp__trello__move_card"
# Hook event: PostToolUse
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes: always 0 (never blocks; informational only)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__move_card" ]]; then
  exit 0
fi

target_list=$(echo "$input" | jq -r '.tool_input.listId // empty')
[[ -z "$target_list" ]] && exit 0

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  # Resolve dest name without API; we can't, so report a degraded message.
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": "Card moved. Could not query Now column — TRELLO_API_KEY and TRELLO_API_TOKEN (or TRELLO_TOKEN) must be set in hook env."
    }
  }'
  exit 0
fi

# Resolve dest list's name + board in one call. `--fail` makes curl exit
# non-zero on HTTP 4xx/5xx so the `|| echo '{}'` fallback engages instead
# of feeding plain-text error bodies into jq. Each jq call also redirects
# stderr and falls back to empty so a malformed response can't abort the
# hook under `set -e`.
dest_meta=$(curl -sf --max-time 5 "https://api.trello.com/1/lists/${target_list}?fields=name,idBoard&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
dest_name=$(echo "$dest_meta" | jq -r '.name // empty' 2>/dev/null || echo "")
board_id=$(echo "$dest_meta" | jq -r '.idBoard // empty' 2>/dev/null || echo "")

[[ -z "$dest_name" || -z "$board_id" ]] && exit 0

dest_lower=$(echo "$dest_name" | tr '[:upper:]' '[:lower:]')

case "$dest_lower" in
  *qa*)
    move_label="moved to Ready for QA"
    ;;
  *research*)
    move_label="bounced to Research and prep"
    ;;
  *)
    # Move went somewhere we don't surface from (e.g., Done, Archive).
    exit 0
    ;;
esac

# Find the Now list on the same board by name.
lists=$(curl -sf --max-time 5 "https://api.trello.com/1/boards/${board_id}/lists?fields=id,name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '[]')
now_list_id=$(echo "$lists" | jq -r '.[] | select((.name | ascii_downcase) | contains("now")) | .id' 2>/dev/null | head -n1 || echo "")

if [[ -z "$now_list_id" ]]; then
  jq -n --arg label "$move_label" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Card " + $label + ". Could not resolve a list named \"Now\" on this board.")
    }
  }'
  exit 0
fi

# Fetch cards in Now with narrowed fields. We take only `.[0]` client-side —
# the Trello `limit=1` query param does NOT respect `pos` ordering (empirically
# tested: returned the wrong card). Omitting `limit` returns cards in `pos`
# order, which is what we need.
response=$(curl -sSf --max-time 10 \
  "https://api.trello.com/1/lists/${now_list_id}/cards?fields=id,idShort,name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" \
  2>/dev/null || echo "")

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
  next_short=$(echo "$response" | jq -r '.[0].idShort')
  next_id=$(echo "$response" | jq -r '.[0].id')
  next_name=$(echo "$response" | jq -r '.[0].name')
  message=$(printf "Card %s. NEXT CARD: #%s %s (id: %s). Call mcp__trello__get_card on this id now. Do NOT pause to ask the user — auto-pickup is the policy." "$move_label" "$next_short" "$next_name" "$next_id")
fi

jq -n --arg msg "$message" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $msg
  }
}'

exit 0
