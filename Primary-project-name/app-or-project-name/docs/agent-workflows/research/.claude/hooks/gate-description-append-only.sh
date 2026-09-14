#!/bin/bash
#
# gate-description-append-only.sh — Claude Code PreToolUse hook
#
# Backstop for Research_Role.md § Card Management § Hard Constraints #3:
# description writes must be append-only. The card description is the
# history and context — research findings, decisions, scope — that
# survives session resets and is the record other roles read against.
# `mcp__trello__update_card_details` replaces the description field
# wholesale; an agent that types a fresh description and submits it has
# wiped the prior content even if "appending" was the intent.
#
# This hook denies any update where the new description does not strictly
# contain the current description as a substring. If the agent has
# read the current desc and concatenated `current + new`, the substring
# check passes. If the agent typed a new full description without the
# read-then-append step, the check fails and the write is blocked.
#
# Fires on mcp__trello__update_card_details only when tool_input.description
# is present. Name-only or label-only updates pass through unaffected.
#
# Matcher in settings.json: "mcp__trello__update_card_details"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - jq or curl missing
#   - env vars missing
#   - card lookup fails (network/auth)
#   - current description is empty (first write — nothing to preserve)
#   - tool_input.description is absent (non-description update)
#
# The fail-open posture mirrors the other gate hooks: a transient API
# blip should not block legitimate work. The constraint also lives in
# prose (Research_Role.md) so the agent is on the discipline when the
# hook can't enforce.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# Shared helper: is_research_column. See lib.sh.
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__update_card_details" ]]; then
  exit 0
fi

# Description not in the update payload (name/label-only update) — nothing to gate.
new_desc=$(echo "$input" | jq -r '.tool_input.description // empty')
[[ -z "$new_desc" ]] && exit 0

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
[[ -z "$card_id" ]] && exit 0

# Fetch current description, card name, and list.
card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=desc,name,idList&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
current_desc=$(echo "$card" | jq -r '.desc // empty')
card_name=$(echo "$card" | jq -r '.name // empty')
id_list=$(echo "$card" | jq -r '.idList // empty')

# Card lookup failed — fail open rather than block on a transient API issue.
[[ -z "$card_name" ]] && exit 0

# First write to a card with no existing description — nothing to preserve, allow.
[[ -z "$current_desc" ]] && exit 0

# Pre-handoff: if the card is still in Research's column, fail open. The
# append-only protection exists to preserve the evidence chain Dev and QA
# read after handoff. While the card is still in Research's column, no other
# role consumes it — corrections (fixing boilerplate, removing wrong sections,
# rewriting) are legitimate work, not destructive wipes. Once the card
# advances out of Research's column, append-only re-engages.
if [[ -n "$id_list" ]]; then
  list_json=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${id_list}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
  list_name=$(echo "$list_json" | jq -r '.name // empty')
  if is_research_column "$list_name"; then
    exit 0
  fi
fi

# Substring check: does the new description contain the current description verbatim?
# Bash [[ ]] string matching handles multi-line content correctly.
if [[ "$new_desc" == *"$current_desc"* ]]; then
  exit 0
fi

# New description does not contain the current — this is a wipe/replacement.
cat >&2 <<EOF
BLOCKED: card "${card_name}" description update would wipe existing content.

The card description is the history and context — research findings,
decisions, scope — that survives session resets and is the record other
roles read against. mcp__trello__update_card_details replaces the
description field wholesale. The submitted description does not contain the
existing description, so existing content would be destroyed.

Research_Role.md § Card Management § Hard Constraints #3: description
writes are append-only by default. The protocol:

  1. mcp__trello__get_card to fetch the current description
  2. Concatenate current + your new content (with a clear section break)
  3. mcp__trello__update_card_details with the combined text

If overwrite is genuinely needed (the user has explicitly directed a
rewrite or restructure), do it through the Trello UI under user direction
or have the user temporarily disable this hook. Don't compose a fresh
description and submit it through the normal write path — that's the
failure mode this hook exists to prevent.
EOF
exit 2
