#!/bin/bash
#
# deny-direct-trello-api.sh — Claude Code PreToolUse hook on Bash
#
# Denies any Bash command that calls the Trello API directly (curl/wget
# against api.trello.com). Forces Trello operations through the MCP tool
# layer (mcp__trello__*) so Dev's column-scope, description-write,
# implementation-notes, and per-card-commit gates run on every change.
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
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# Match actual HTTP calls to Trello: an https?:// URL whose host is
# api.trello.com. Requiring the scheme avoids false positives where "curl"
# and "api.trello.com" appear in prose (help messages, comments, heredocs
# writing settings/hook files), which a broader pattern catches. Case-
# insensitive to catch HTTPS/API.TRELLO.COM variants.
if echo "$cmd" | grep -qiE 'https?://api\.trello\.com'; then
  cat >&2 <<'EOF'
BLOCKED: direct Trello API call from Bash.

Use the MCP Trello tools (mcp__trello__*) instead of curl/wget to
api.trello.com. Direct API calls bypass Dev's enforcement hooks:
  - gate-column-scope.sh        (update only cards in "Now")
  - block-description-writes.sh (no description writes — that's Research's)
  - gate-implementation-notes.sh (§6 notes required on move to Ready for QA)
  - gate-per-card-commit.sh     (#<card> commit subject on move to Ready for QA)
  - apply-needs-research-label.sh (label-on-bounce to Research and prep)

All enforcement hooks are scoped to mcp__trello__* matchers. Bypassing
MCP means none of them run on your changes.

If batch operations are slow, send multiple mcp__trello__* calls in
parallel (one message, multiple tool uses) — don't shell out. The
read-only column watcher is exempt: it runs via the Monitor tool.
EOF
  exit 2
fi

exit 0
