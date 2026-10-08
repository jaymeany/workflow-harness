#!/bin/bash
#
# deny-direct-trello-api.sh — Claude Code PreToolUse hook on Bash
#
# Denies any Bash command that calls the Trello API directly (curl/wget
# against api.trello.com). Forces Trello operations through the MCP tool
# layer (mcp__trello__*) so the structural-gate, research-complete, and
# QA-compliance hooks run on every change.
#
# Why: the other hooks in this directory all match on mcp__trello__* tool
# names. A Bash `curl https://api.trello.com/...` bypasses them entirely —
# not through a bug but because the enforcement is wrapped around the MCP
# tool, not the API endpoint. This hook closes that gap by rejecting the
# bypass pattern at the Bash tool layer.
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

# Match actual HTTP calls to the board's API: a URL with a scheme whose host is
# the API host (BOARD_API_URL_ERE in the adapter's tools.conf). Requiring the
# scheme avoids false positives where a client name and the host appear in
# prose (help messages, comments, heredocs writing settings files).
# Case-insensitive to catch upper-case variants.
if echo "$cmd" | grep -qiE "$BOARD_API_URL_ERE"; then
  cat >&2 <<'EOF'
BLOCKED: direct Trello API call from Bash.

Use the MCP Trello tools (mcp__trello__*) instead of curl/wget to
api.trello.com. Direct API calls bypass:
  - gate-research-complete.sh (marker + blocker validation)
  - gate-card-structure.sh (header allowlist + file-count cap)
  - qa-protocol-compliance.sh (QA comment validation)
  - apply-research-complete-label.sh (label-on-create)

All enforcement hooks are scoped to mcp__trello__* matchers. Bypassing
MCP means structural enforcement doesn't run on your changes.

If batch operations are slow, send multiple mcp__trello__* calls in
parallel (one message, multiple tool uses) — don't shell out.
EOF
  exit 2
fi

exit 0
