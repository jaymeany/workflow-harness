#!/bin/bash
#
# enforce-card-naming.sh — Claude Code PreToolUse hook on
# mcp__trello__(add_card_to_list|update_card_details).
#
# Cards on this board follow:
#
#   #<idShort> <title> <24-char-trello-api-id>
#
# Three parts. Fires on both creation and rename so a malformed convention
# name can't slip through at create time and stay live until someone renames.
# When the candidate name starts with `#`, validate the full pattern. The most
# common slip is a typo in the trello_api_id: it's the 24-character Trello
# `id` field, not `idShort`. Names that don't begin with `#` are unaffected —
# placeholder names at create time (e.g., "TBD", a draft title) pass through;
# the rename to the convention happens once Trello assigns idShort and id.
#
# THERE IS NO FOURTH FIELD. A worktree suffix naming the repo a card belongs to
# is a convention from multi-repo boards; on a single board it distinguishes
# nothing. A trailing suffix is TOLERATED, NOT REQUIRED. New cards use three
# parts.
#
# Edits without a `name` field (description-only updates, list moves)
# are unaffected.
#
# Matcher in settings.json:
#   "mcp__trello__(update_card_details|add_card_to_list)"
#
# Requires: jq
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message

# Requires-Path: ../board/board.sh
# Board-Actions: update, create

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names, the tool-call reader, the card id format.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
case "$HOOK_ACTION" in
  update|create) ;;
  *) exit 0 ;;
esac

new_name="$HOOK_NAME"

# Only validate when the rename appears to be using the convention.
if [[ -z "$new_name" || "${new_name:0:1}" != "#" ]]; then
  exit 0
fi

# Convention regex:
#   ^#                       — leading hash
#   [0-9]+                   — card number (digits)
#   [[:space:]]              — separator
#   .+                       — title (greedy; can contain spaces)
#   [[:space:]]              — separator
#   BOARD_CARD_ID_ERE        — the card id, in the adapter's format
#                              (Trello: 24 lowercase hex characters)
#   (...)?$                  — an OPTIONAL trailing legacy suffix, see above
if ! [[ "$new_name" =~ ^#[0-9]+[[:space:]].+[[:space:]]${BOARD_CARD_ID_ERE}([[:space:]][A-Za-z0-9_-]+)?$ ]]; then
  cat >&2 <<EOF
BLOCKED: card name "$new_name" doesn't match the naming convention.

Convention: #<idShort> <title> <24-char-trello-api-id>
Example:    #12 Establish per-card git commit discipline PLACEHOLDER_TRELLO_ID

Three parts. There is no fourth field.

Common slips:
  - trello_api_id is the 24-character Trello \`id\` field, not \`idShort\`
  - idShort goes immediately after the \`#\`, no space

See the role doc's "Card Naming Convention" section for the full schema.
EOF
  exit 2
fi

exit 0
