#!/bin/bash
#
# deny-trello-comments.sh — Claude Code PreToolUse hook
#
# Backstop for Research_Role.md § Card Management § Hard Constraints:
# Research findings go in the card description, not in comments. Comments
# are Dev's and QA's channel for implementation notes and review status —
# findings posted there get lost in their workflow because they read the
# description and skim the comments. The constraint is prose-level; this
# hook makes it hard to violate by accident.
#
# Fires on any Trello comment-mutation tool: add_comment, update_comment,
# delete_comment.
#
# Matcher in settings.json: "mcp__trello__(add_comment|update_comment|delete_comment)"
#
# Requires: jq
#
# Exit codes:
#   0 — allow (only if matcher misfires; defensive)
#   2 — deny with stderr message

# Requires-Path: ../board/board.sh
# Board-Actions: comment, comment_edit, comment_delete

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names and the tool-call reader.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
case "$HOOK_ACTION" in
  comment|comment_edit|comment_delete) ;;
  *) exit 0 ;;
esac

cat >&2 <<'EOF'
BLOCKED: Research does not write Trello comments.

Comments are Dev's and QA's channel for implementation notes and review
status. Findings posted by Research as comments get lost in their workflow —
they read the description, they skim the comments. Research findings go in
the description so they survive the handoff.

If the finding belongs on this card, append it to the description with
`mcp__trello__update_card_details` (after fetching the current desc and
preserving existing content).

If the question is for Dev or QA mid-stream, route through the user.

See Research_Role.md § Card Management § Hard Constraints.
EOF
exit 2
