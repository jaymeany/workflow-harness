#!/bin/bash
#
# apply-tracking-label.sh — Claude Code PostToolUse hook
#
# When QA creates a card — always a tracking card for future work surfaced
# during review — apply two defaults atomically at create time:
#
#   1. The "Tracking" label. The board adapter decides how it is found; on
#      Trello it is the orange label, matched by COLOR ONLY, never by name.
#   2. Conventional name `#<number> <currentName> <id> dev` if the card
#      was created with a placeholder (non-`#`-prefixed) name.
#
# Why both at create time: the convention requires the board's assigned card
# number and id, neither of which exist before creation. The hook is the
# only place that has the create-response in hand and can apply both the
# label and the conventional name atomically — no transient state where
# the card sits with a placeholder name visible to other roles.
#
# Non-fatal: label lookup, label apply, name fetch, and rename failures all
# silent-no-op rather than block. The card is already created by the time
# this hook runs.
#
# tool_response shape: MCP tools return `tool_response` as an array of
# content blocks `[{type, text}]` where the JSON-stringified card sits in
# `text`. Plain-object responses are also accepted. The board layer reads
# both.
#
# Matcher in settings.json: the board's create tool.
# Hook event: PostToolUse
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
# Requires-Path: ../board/board.sh
# Board-Actions: create
#
# Exit codes: always 0 (non-blocking; informational side-effect only)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names, board calls and the tool-call reader.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
if [[ "$HOOK_ACTION" != "create" ]]; then
  exit 0
fi

board_credentials_present || exit 0

card_id="$HOOK_CREATED_ID"
if [[ -z "$card_id" ]]; then
  exit 0
fi

board_id="$HOOK_CREATED_BOARD_ID"
if [[ -z "$board_id" ]]; then
  board_card_get card "$card_id"
  if [[ -n "$card" ]]; then
    board_id=$(printf '%s' "$card" | jq -r '.board_id // empty')
  fi
fi
if [[ -z "$board_id" ]]; then
  exit 0
fi

# ---- 1. "Tracking" label ----
board_labels labels "$board_id"
board_state_label_pick label_id "${labels:-[]}" tracking

if [[ -n "$label_id" ]]; then
  board_card_label_add "$card_id" "$label_id"
fi

# ---- 2. Convention rename ----
# Only rename when the current name is a placeholder (no leading `#`). If
# the caller passed a `#`-prefixed name, enforce-card-naming.sh has already
# validated it at create time — don't clobber.
current_name="$HOOK_CREATED_TITLE"
id_short="$HOOK_CREATED_NUMBER"

if [[ -n "$current_name" && "${current_name:0:1}" != "#" && -n "$id_short" ]]; then
  # Worktree shortname is hardcoded to "dev" — matches the QA default for
  # tracking-card names per the harness memory.
  worktree="dev"
  new_name="#${id_short} ${current_name} ${card_id} ${worktree}"
  board_card_rename "$card_id" "$new_name"
fi

exit 0
