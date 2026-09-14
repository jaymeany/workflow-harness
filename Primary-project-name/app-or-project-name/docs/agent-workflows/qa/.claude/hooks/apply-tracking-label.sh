#!/bin/bash
#
# apply-tracking-label.sh — Claude Code PostToolUse hook
#
# When QA creates a card — always a tracking card for future work surfaced
# during review — apply two defaults atomically at create time:
#
#   1. Orange "Tracking" label — matched by COLOR ONLY, never by name.
#      Label semantics on this board are carried by color; the labels are
#      unnamed (name == ""). An earlier revision also required
#      `name == "tracking"`, which matched nothing and silent-no-op'd the
#      apply on every tracking card ever created.
#   2. Conventional name `#<idShort> <currentName> <id> dev` if the card
#      was created with a placeholder (non-`#`-prefixed) name.
#
# Why both at create time: the convention requires Trello's assigned idShort
# and 24-char id, neither of which exist before creation. The hook is the
# only place that has the create-response in hand and can apply both the
# label and the conventional name atomically — no transient state where
# the card sits with a placeholder name visible to other roles. (A
# follow-up rename via update_card_details is also possible after the
# gate-done-immutable.sh refactor, but doing it here avoids the window
# where the card is mis-named.)
#
# Non-fatal: label lookup, label apply, name fetch, and rename failures all
# silent-no-op rather than block. The card is already created by the time
# this hook runs.
#
# tool_response shape: MCP tools return `tool_response` as an array of
# content blocks `[{type, text}]` where the JSON-stringified card sits in
# `text`. Plain-object responses (`tool_response.id` direct) are also
# accepted as a fallback so the hook works under both shapes. Earlier
# revisions read only the plain-object shape and silent-no-op'd on every
# real MCP call — fixed.
#
# Matcher in settings.json: "mcp__trello__add_card_to_list"
# Hook event: PostToolUse
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

if [[ "$tool_name" != "mcp__trello__add_card_to_list" ]]; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# Resolve the response payload as a flat JSON object regardless of whether
# the harness passed it directly (plain object) or wrapped in MCP's content
# array shape (`[{type:"text", text:"<json>"}]`).
response_obj=$(echo "$input" | jq -c '
  if (.tool_response | type) == "object" then .tool_response
  elif (.tool_response | type) == "array" and (.tool_response | length) > 0
       and (.tool_response[0].text // null) != null
  then (.tool_response[0].text | fromjson)
  else null
  end
')

if [[ -z "$response_obj" || "$response_obj" == "null" ]]; then
  exit 0
fi

card_id=$(echo "$response_obj" | jq -r '.id // empty')
if [[ -z "$card_id" ]]; then
  exit 0
fi

board_id=$(echo "$response_obj" | jq -r '.idBoard // empty')
if [[ -z "$board_id" ]]; then
  board_id=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idBoard&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null | jq -r '.idBoard // empty')
fi
if [[ -z "$board_id" ]]; then
  exit 0
fi

# ---- 1. Orange "Tracking" label ----
labels=$(curl -s --max-time 5 "https://api.trello.com/1/boards/${board_id}/labels?key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '[]')
label_id=$(printf '%s' "$labels" | jq -r '.[] | select(.color=="orange") | .id' 2>/dev/null | head -n1)

if [[ -n "$label_id" ]]; then
  curl -s --max-time 5 -X POST \
    "https://api.trello.com/1/cards/${card_id}/idLabels?value=${label_id}&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" \
    >/dev/null 2>&1 || true
fi

# ---- 2. Convention rename ----
# Only rename when the current name is a placeholder (no leading `#`). If
# the caller passed a `#`-prefixed name, enforce-card-naming.sh has already
# validated it at create time — don't clobber.
current_name=$(echo "$response_obj" | jq -r '.name // empty')
id_short=$(echo "$response_obj" | jq -r '.idShort // empty')

if [[ -n "$current_name" && "${current_name:0:1}" != "#" && -n "$id_short" ]]; then
  # Worktree shortname is hardcoded to "dev" — matches the QA default for
  # tracking-card names per the harness memory.
  worktree="dev"
  new_name="#${id_short} ${current_name} ${card_id} ${worktree}"

  # PUT /cards/{id} with name. URL-encode the value via curl --data-urlencode.
  curl -s --max-time 5 -X PUT \
    --data-urlencode "name=${new_name}" \
    "https://api.trello.com/1/cards/${card_id}?key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" \
    >/dev/null 2>&1 || true
fi

exit 0
