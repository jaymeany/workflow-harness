#!/bin/bash
#
# deny-direct-trello-api.sh — Claude Code PreToolUse hook on Bash
#
# Denies any Bash command that calls the Trello API directly (curl/wget
# against api.trello.com). The other hooks in this folder match on
# mcp__trello__* tool names; a Bash `curl https://api.trello.com/...`
# bypasses them entirely because the enforcement is wrapped around the
# MCP tool, not the API endpoint. This hook closes that gap by rejecting
# the bypass pattern at the Bash tool layer.
#
# Matcher in settings.json: "Bash"
#
# What's allowed:
#   - mcp__trello__* tool calls (unaffected — different tool)
#   - Hook scripts calling the Trello API (they're invoked by Claude Code,
#     not by Claude via Bash — they don't route through this hook)
#   - Bash commands that don't mention api.trello.com
#
# What's blocked:
#   - curl / wget / http / https / fetch commands whose arg contains
#     "api.trello.com"
#
# Requires: jq
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message

# Requires-Path: ../board/board.sh
# Board-Actions: shell

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# The board layer: the tool-call reader and the board's API address.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
[[ "$HOOK_ACTION" == "shell" ]] || exit 0

cmd="$HOOK_COMMAND"

# Match any HTTP-client command (curl, wget, http, https, fetch) that
# references the board's API host (BOARD_API_HOST_ERE in the adapter's
# tools.conf) in the same command. Case-insensitive. Broad match on HTTP
# clients to cover heredocs and pipes.
if echo "$cmd" | grep -qiE "(curl|wget|\bhttp\b|\bhttps\b|\bfetch\b)[^|;&]*${BOARD_API_HOST_ERE}"; then
  cat >&2 <<'EOF'
BLOCKED: direct Trello API call from Bash.

Use the MCP Trello tools (mcp__trello__*) instead of curl/wget to
api.trello.com. Direct API calls bypass the QA enforcement hooks:
  - gate-done-immutable.sh     (no edits to cards in "Done")
  - block-description-writes.sh (no description writes in any column)
  - enforce-card-naming.sh     (#<idShort> <title> <id> <worktree> convention)
  - qa-protocol-compliance.sh  (§9 comment validation on move_card)
  - apply-tracking-label.sh    (orange Tracking label on new cards)
  - qa-post-move.sh            (queue surface after Done/Now moves)

All enforcement hooks are scoped to mcp__trello__* matchers. Bypassing
MCP means none of them run on your changes.

If batch operations are slow, send multiple mcp__trello__* calls in
parallel (one message, multiple tool uses) — don't shell out.
EOF
  exit 2
fi

exit 0
