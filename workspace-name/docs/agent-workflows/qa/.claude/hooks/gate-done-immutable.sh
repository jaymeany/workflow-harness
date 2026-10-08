#!/bin/bash
#
# gate-done-immutable.sh — Claude Code PreToolUse hook on
# mcp__trello__update_card_details.
#
# Cards in "Done" are the QA-blessed final record of what shipped. Editing
# them rewrites the audit trail. If new scope surfaces, the answer is a
# tracking card via add_card_to_list, not an edit to the Done card.
#
# This hook is the narrow Done-immutable enforcement only. It does NOT
# restrict QA writes by column — the broader description-clobber concern
# is covered by the sibling block-description-writes.sh hook (which
# denies any update_card_details with tool_input.description set, in
# every column). With descriptions locked everywhere, the remaining
# legitimate writes (name, labels, dueDate, dueComplete, start) are
# allowed in any column EXCEPT Done.
#
# This unblocks the documented tracking-card naming convention from
# QA_Role.md (§ Card Naming Convention): QA creates a tracking card via
# add_card_to_list (which gets only a placeholder name because Trello
# assigns idShort + id at create time), then immediately renames it via
# update_card_details to `#<idShort> <title> <24-hex trello_api_id>
# <worktree>`. The tracking card lands in "Research and prep" (or "Now"
# for urgent findings); without this loosening, that follow-up rename
# was blocked by the predecessor gate-column-scope.sh.
#
# Allow: list name does not match `^done$` case-insensitively.
# Deny:  list name is "Done".
#
# Matcher in settings.json: "mcp__trello__update_card_details"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Fails open if jq/curl missing or env unset — verifying a card's column
# without those isn't possible, and blocking legitimate work on a
# tooling gap is worse than letting an edit through. The fail-open
# posture is documented in CLAUDE.md so the gate's coverage isn't taken
# for granted.
#
# Requires: jq, curl
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message

# Requires-Path: ../board/board.sh
# Board-Actions: update

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0  # Dependency missing; fail open.
fi

# The board layer: tool names, board calls and the column rule.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
[[ "$HOOK_ACTION" == "update" ]] || exit 0

card_id="$HOOK_CARD_ID"
[[ -n "$card_id" ]] || exit 0

board_credentials_present || exit 0  # Cannot verify; fail open.

board_card_stage_name list_name "$card_id"
[[ -n "$list_name" ]] || exit 0  # Could not read the column; fail open.

board_column_is "$list_name" done || exit 0

cat >&2 <<EOF
BLOCKED: cannot modify card in "Done" — Done is immutable.

Cards in "Done" are the QA-blessed final record of what shipped.
Editing them rewrites the audit trail. If new scope surfaces on a
shipped card, create a tracking card via mcp__trello__add_card_to_list
(a different tool, not gated by this hook). Reference the source card
by number/id from the tracking card's description. The orange
"Tracking" label is applied automatically.
EOF
exit 2
