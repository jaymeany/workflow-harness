#!/bin/bash
#
# deny-direct-trello-api.sh — Claude Code PreToolUse hook on Bash
#
# Denies any Bash command that calls the Trello API directly (curl/wget
# against api.trello.com). Forces Trello operations through the MCP tool
# layer (mcp__trello__*) so this role's board gates run on every change.
# The same file serves the orchestrator, Designer and Dev, so the message
# names no one role's hooks.
#
# Why: every Trello gate in this directory matches on mcp__trello__* tool
# names. A Bash `curl https://api.trello.com/...` bypasses them entirely —
# not through a bug but because the enforcement is wrapped around the MCP
# tool, not the API endpoint. This hook closes that gap at the Bash layer.
#
# Matcher in settings.json: "Bash"
#
# What's allowed:
#   - mcp__trello__* tool calls (unaffected — different tool)
#   - The read-only Trello column watcher: it
#     runs via the Monitor tool, not Bash, so it never routes through this
#     hook. Card OPERATIONS stay on mcp__trello__* — this gate stands.
#   - Hook scripts calling the Trello API (invoked by Claude Code, not by
#     Claude via Bash — they don't route through this hook)
#   - Bash commands that don't contain an https?://api.trello.com URL
#
# What's blocked:
#   - Any Bash command containing an https?://api.trello.com URL
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

# Match actual HTTP calls to the board's API: a URL with a scheme whose host is
# the API host (BOARD_API_URL_ERE in the adapter's tools.conf). Requiring the
# scheme avoids false positives where a client name and the host appear in
# prose (help messages, comments, heredocs writing settings or hook files).
# Case-insensitive to catch upper-case variants.
if echo "$cmd" | grep -qiE "$BOARD_API_URL_ERE"; then
  cat >&2 <<'EOF'
BLOCKED: direct Trello API call from Bash.

Use the MCP Trello tools (mcp__trello__*) instead of curl or wget to
api.trello.com. This role's board gates in .claude/hooks/ match on
mcp__trello__* tool names, so a direct API call skips all of them.

If batch operations are slow, send several mcp__trello__* calls in
parallel, in one message. Do not shell out. The read-only column
watcher is exempt: it runs via the Monitor tool.
EOF
  exit 2
fi

exit 0
