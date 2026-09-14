#!/bin/bash
#
# qa-deferral-phrase-surfacer.sh — Claude Code PreToolUse hook on
# mcp__trello__add_comment.
#
# Codifies QA_Decisions.md §8 "Findings Tracking":
# QA review comments cannot ship deferral phrases ("non-blocking note",
# "minor gap", "fold into next pass", "out of scope", "follow-on", "future
# work observation", etc.) without a #<n> tracking-card citation on the
# same line.
#
# A deferral phrase without a tracked card is a silent scope cut — the
# finding vanishes from session memory, never gets prioritized, and becomes
# tomorrow's incident. See QA_Decisions.md §8 "Findings Tracking".
#
# Only fires on comments whose body starts with "## QA Review" (the §9
# template signature). Non-QA comments — tracking-card replies, research
# notes, side commentary — are out of scope; phrases like "out of scope"
# are legitimate prose there.
#
# Algorithm:
#   For each line in the comment body, case-insensitively scan for any
#   flagged phrase. If a phrase is present, the same line must also
#   contain a `#<digits>` reference (a tracking card number). Lines with
#   a phrase but no citation are reported in the block reason.
#
# Same-line scoping is intentional: it forces QA to put the citation
# next to the phrase rather than rely on a generic "Tracking Cards
# Created: #N" footer that may or may not correspond to the deferral.
#
# Matcher in settings.json: "mcp__trello__add_comment"
#
# Requires: jq
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if jq missing.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" != "mcp__trello__add_comment" ]]; then
  exit 0
fi

text=$(echo "$input" | jq -r '.tool_input.text // empty')

# Filter on QA review comments only. The §9 template starts with
# "## QA Review"; anything else is out of scope for this hook.
if [[ "$text" != "## QA Review"* ]]; then
  exit 0
fi

# Phrases that signal a deferred finding without tracking. Each match below
# is treated case-insensitively. Edit this list in sync with QA_Decisions.md
# §8 — adding a phrase here without updating the doc creates a surprise deny.
PHRASES=(
  "non-blocking note"
  "non-blocking observation"
  "minor gap"
  "minor note"
  "fold into next pass"
  "out of scope"
  "follow-on"
  "follow up later"
  "future work observation"
  "future work"
)

# Build a single ERE pattern from the phrase list.
pattern=""
for p in "${PHRASES[@]}"; do
  if [[ -z "$pattern" ]]; then
    pattern="$p"
  else
    pattern="${pattern}|${p}"
  fi
done

# Scan each line. A line with a flagged phrase must also contain `#<digits>`.
violations=()
while IFS= read -r line; do
  if echo "$line" | grep -iE "$pattern" >/dev/null 2>&1; then
    if ! echo "$line" | grep -E '#[0-9]+' >/dev/null 2>&1; then
      violations+=("$line")
    fi
  fi
done <<< "$text"

if [[ ${#violations[@]} -eq 0 ]]; then
  exit 0
fi

{
  cat <<'EOF'
BLOCKED: QA review comment contains deferral phrases without tracking-card citations.

Every finding surfaced during review gets a Trello tracking card before the
QA comment goes up. A deferral phrase without a tracked card is a silent
scope cut — the finding vanishes from session memory and becomes tomorrow's
incident. See QA_Decisions.md §8 "Findings Tracking".

Lines flagged (each must cite a #<n> tracking card on the same line):

EOF
  for v in "${violations[@]}"; do
    printf '  > %s\n' "$v"
  done
  cat <<'EOF'

To proceed:
  1. For each flagged finding, create a tracking card via
     mcp__trello__add_card_to_list (lands in "Research" or "Now").
  2. Edit the QA comment so the flagged line cites the new card's #<n>
     inline. Example:
        - Auth scope check missing for org switch (#142)
  3. Re-submit the comment.

If a flagged phrase is genuinely not a deferral (e.g., quoting a card
title that contains the phrase), include any #<n> on the same line — the
hook checks for the presence of a citation, not its semantics.
EOF
} >&2

exit 2
