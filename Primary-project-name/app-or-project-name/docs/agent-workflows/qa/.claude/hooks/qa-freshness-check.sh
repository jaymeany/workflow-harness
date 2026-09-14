#!/bin/bash
#
# qa-freshness-check.sh — Claude Code PreToolUse hook on
# mcp__trello__move_card.
#
# Catches the stale-state QA review failure mode: Dev modifies the card
# (new "## Implementation Notes" or "## Design Notes" comment, description
# edit) AFTER QA's
# latest review comment was written. Moving the card based on that review
# would PASS or FAIL the wrong code.
#
# Algorithm:
#   1. Resolve the source list. Only fire on moves originating from
#      "Ready for QA".
#   2. Pull the card's recent actions (commentCard + updateCard).
#   3. Find the latest "## QA Review" commentCard timestamp. Use
#      `dateLastEdited // .date` so a freshly-edited QA comment counts
#      as the new reference point.
#   4. Find any newer activity that could invalidate the review:
#        - commentCard whose body starts with "## Implementation Notes" or
#          "## Design Notes". Both: Design hands off under its own heading
#          and a review can go stale on a Design card exactly as it can on
#          a Dev one.
#        - updateCard with a description change (data.old.desc set)
#   5. If newer activity exists, deny with a refresh instruction.
#
# Companion to qa-protocol-compliance.sh (which validates §9 template
# compliance at the same trigger point) — this hook is the temporal
# correctness check; protocol-compliance is the format check. Order in
# settings.json doesn't matter; both must pass.
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
# Fails open (allow) if jq/curl/env missing — the alternative (blocking
# legitimate moves on a tooling gap) is worse than letting an edit
# through. Same posture as the other hooks in this folder.

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
if [[ -z "$card_id" ]]; then
  exit 0
fi

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# Resolve source list. Only gate moves out of "Ready for QA".
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

# Pull commentCard + updateCard actions, newest first.
actions=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}/actions?filter=commentCard,updateCard&limit=50&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '[]')

# Latest QA review timestamp. Prefer dateLastEdited so a refreshed comment
# counts as the new reference point.
qa_ts=$(echo "$actions" | jq -r '
  [.[] | select(.type == "commentCard" and (.data.text // "" | startswith("## QA Review")))][0]
  | (.data.dateLastEdited // .date) // empty
')

if [[ -z "$qa_ts" ]]; then
  # No QA review found. The protocol-compliance hook will catch this on
  # its own; pass through here.
  exit 0
fi

# Newer Dev-side activity that would invalidate the review.
stale_action=$(echo "$actions" | jq -r --arg qa "$qa_ts" '
  [.[]
    | select(
        (.type == "commentCard" and (.data.text // "" | test("^## (Implementation|Design) Notes")))
        or (.type == "updateCard" and (.data.old | has("desc")))
      )
    | select(.date > $qa)
  ]
  | sort_by(.date)
  | last
  | if . == null then empty
    else "\(.type)|\(.date)|\((.data.text // .data.old.desc // "") | gsub("\n"; " ") | .[0:120])"
    end
')

if [[ -z "$stale_action" ]]; then
  exit 0
fi

stale_type=$(echo "$stale_action" | awk -F'|' '{print $1}')
stale_date=$(echo "$stale_action" | awk -F'|' '{print $2}')
stale_preview=$(echo "$stale_action" | awk -F'|' '{for(i=3;i<=NF;i++){printf "%s%s", $i, (i<NF?"|":"")}}')

case "$stale_type" in
  commentCard)
    stale_desc="A new \"## Implementation Notes\" or \"## Design Notes\" comment was posted"
    ;;
  updateCard)
    stale_desc="Dev edited the card description"
    ;;
  *)
    stale_desc="Dev modified the card"
    ;;
esac

cat >&2 <<EOF
BLOCKED: stale QA review — card has been modified since the last review.

Latest QA review timestamp:  $qa_ts
Newer activity:              $stale_date  ($stale_desc)
Preview:                     $stale_preview

Moving the card now would apply a review written against state that has
since been overwritten. Refresh the review before moving:

  1. Re-read the changed files at HEAD.
  2. Re-read the latest "## Implementation Notes" or "## Design Notes" comment.
  3. Post a new "## QA Review" comment that reflects the current state
     (do NOT edit the prior review — post a fresh one so the timeline
     stays auditable).
  4. Re-issue the move.

If you have already done all that and believe this is a false positive
(e.g., the newer activity was your own correction), re-edit your QA review
comment so its dateLastEdited is newer than the Dev activity, then re-issue
the move.
EOF

exit 2
