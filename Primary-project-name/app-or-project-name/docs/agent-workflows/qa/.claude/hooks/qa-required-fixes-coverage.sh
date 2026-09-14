#!/bin/bash
#
# qa-required-fixes-coverage.sh — Claude Code PreToolUse hook on
# mcp__trello__move_card.
#
# Catches the iteration-2-without-fixes failure mode: Dev re-handoffs a
# card to "Ready for QA" within seconds of QA's prior FAIL, QA reviews
# and PASSes without verifying that each prior Required Fix was actually
# addressed. The fix items vanish across iteration boundaries, the bug
# ships, the audit trail says PASS.
#
# Algorithm:
#   1. Only fire on move_card from "Ready for QA" → "Done".
#   2. Read the latest "## QA Review" comment. If **Iteration**: 1 (or
#      missing), there is no prior FAIL to verify against — pass through.
#   3. For Iteration N >= 2, find the most recent prior QA Review comment
#      with **Status**: FAIL and a "### Required Fixes" section. Count
#      the numbered/bulleted items in that section.
#   4. The current PASS comment must include an "### Iteration N Fixes
#      Addressed" section with at least as many items, where N matches
#      the current Iteration value.
#   5. Item count match alone is a weak check — but it forces QA to
#      explicitly enumerate verification of each prior fix, which is
#      the discipline this hook is enforcing.
#
# Companion to qa-protocol-compliance.sh — that hook validates §9 template
# format on move; this hook validates iteration-to-iteration continuity
# of the fix-verification record. Both fire on the same trigger; order
# in settings.json doesn't matter.
#
# Matcher in settings.json: "mcp__trello__move_card"
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
# Fails open (allow) if jq/curl/env missing, same posture as siblings.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__move_card" ]]; then
  exit 0
fi

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
dest_list_id=$(echo "$input" | jq -r '.tool_input.listId // empty')
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# Source list filter — only Ready for QA.
card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idList&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '{}')
source_list_id=$(echo "$card" | jq -r '.idList // empty')
if [[ -z "$source_list_id" ]]; then
  exit 0
fi

source_list_name=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${source_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null \
  | jq -r '.name // empty' \
  | tr '[:upper:]' '[:lower:]')

if ! printf '%s' "$source_list_name" | grep -qiE '(^|[^[:alnum:]])qa([^[:alnum:]]|$)'; then
  exit 0
fi

# Destination filter — only Done. FAIL/BOUNCE moves don't need fix-coverage.
dest_list_name=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${dest_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null \
  | jq -r '.name // empty' \
  | tr '[:upper:]' '[:lower:]')

if ! printf '%s' "$dest_list_name" | grep -qiE '(^|[^[:alnum:]])done([^[:alnum:]]|$)'; then
  exit 0
fi

# Pull QA review comments, newest first.
comments=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}/actions?filter=commentCard&limit=50&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '[]')

# Latest QA Review.
latest_qa=$(echo "$comments" | jq -r '
  [.[] | select(.data.text != null and (.data.text | startswith("## QA Review")))][0].data.text // empty
')

if [[ -z "$latest_qa" ]]; then
  # No QA review at all — protocol-compliance hook will catch this. Pass.
  exit 0
fi

# Parse iteration value from the latest QA review.
iteration=$(echo "$latest_qa" | grep -E '^\*\*Iteration\*\*:' | head -n1 \
  | sed -E 's/^\*\*Iteration\*\*:[[:space:]]*//; s/[^0-9].*$//')

if [[ -z "$iteration" ]] || ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
  # Iteration field missing or unparseable. Protocol-compliance handles
  # template format; pass through here rather than double-bounce.
  exit 0
fi

if [[ "$iteration" -lt 2 ]]; then
  # First iteration — no prior fixes to verify.
  exit 0
fi

# Most recent prior QA Review with Status: FAIL.
prior_fail=$(echo "$comments" | jq -r '
  [.[] | select(
    .data.text != null
    and (.data.text | startswith("## QA Review"))
    and (.data.text | test("\\*\\*Status\\*\\*:\\s*FAIL"))
  )][0].data.text // empty
')

if [[ -z "$prior_fail" ]]; then
  # Iteration says >=2 but no prior FAIL exists. Could be a numbering
  # mistake; let it through rather than block on a missing predecessor.
  exit 0
fi

# Count items in the prior FAIL's Required Fixes section. Items are either
# numbered ("1. foo", "2. bar") or bulleted ("- foo", "- bar"). Strip the
# section heading line itself and stop at the next "###" boundary.
prior_fix_count=$(echo "$prior_fail" | awk '
  /^### Required Fixes/ { flag = 1; next }
  /^### / { flag = 0 }
  flag
' | grep -cE '^[[:space:]]*([0-9]+\.|-)[[:space:]]+\S')

if [[ "$prior_fix_count" -lt 1 ]]; then
  # Prior FAIL had no enumerable fixes — nothing to verify. Pass.
  exit 0
fi

# Latest PASS comment must include "### Iteration N Fixes Addressed" with
# at least prior_fix_count items.
addressed_section_pattern="^### Iteration ${iteration} Fixes Addressed"
if ! echo "$latest_qa" | grep -qE "$addressed_section_pattern"; then
  cat >&2 <<EOF
BLOCKED: iteration-${iteration} PASS missing required fix-verification section.

The prior FAIL listed ${prior_fix_count} required fix(es). Before moving
to Done, the latest QA review comment must include:

  ### Iteration ${iteration} Fixes Addressed
  1. [Required Fix 1 from prior FAIL]: verified at file:line — explanation
  2. [Required Fix 2 from prior FAIL]: verified at file:line — explanation

Each prior fix needs explicit verification. Counting prior fixes only
forces enumeration; the substance is QA's responsibility. See QA_Decisions.md
§9 PASS variant.

If you reviewed but cannot verify a prior fix, this is FAIL → Now (set
**Status**: FAIL and add a Required Fixes section), not PASS.
EOF
  exit 2
fi

addressed_count=$(echo "$latest_qa" | awk -v hdr="^### Iteration ${iteration} Fixes Addressed" '
  $0 ~ hdr { flag = 1; next }
  /^### / { flag = 0 }
  flag
' | grep -cE '^[[:space:]]*([0-9]+\.|-)[[:space:]]+\S')

if [[ "$addressed_count" -lt "$prior_fix_count" ]]; then
  cat >&2 <<EOF
BLOCKED: Iteration ${iteration} Fixes Addressed section is incomplete.

Prior FAIL required fixes:    ${prior_fix_count}
Items in PASS Fixes Addressed: ${addressed_count}

Each prior Required Fix must have a corresponding addressed item with a
file:line citation. See QA_Decisions.md §9 PASS variant.

If a prior fix was determined to be N/A or invalid on re-review, document
that explicitly as an item — the count must still match.
EOF
  exit 2
fi

exit 0
