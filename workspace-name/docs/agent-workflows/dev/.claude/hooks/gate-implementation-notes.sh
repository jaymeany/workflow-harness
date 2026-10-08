#!/bin/bash
#
# gate-implementation-notes.sh — Claude Code PreToolUse hook
#
# Move-time validation of Dev's handoff artifact. Fires on
# mcp__trello__move_card when the destination list is "Ready for QA".
# Validates that the card's most-recent comment contains a complete §6
# Implementation Notes block. Same shape QA's qa-protocol-compliance.sh
# enforces on the way out, but for Dev's way in.
#
# The artifact lives in a comment, not the description: Dev_Role.md and
# Dev_Protocol.md §6 establish that Dev writes only to comments — the
# card description is Research's evidence chain. Implementation Notes
# go in the comment Dev posts via mcp__trello__add_comment immediately
# before moving the card.
#
# Failure mode: handing off to QA without a complete artifact wastes
# QA's review cycle and lets §5 Definition of Done violations slip
# through unflagged. The §6 template exists so QA can audit Dev's work
# against a known structure; without it, QA has to reverse-engineer
# scope, services, and tests from the diff alone.
#
# Validates the §6 template inside the latest comment:
#   - "## Implementation Notes ..." top-level header (anything after the dash)
#   - "### Services Used" with ≥ 1 non-placeholder bullet
#   - "### Testing Done" with ≥ 1 "- [x]" line that isn't a placeholder
#   - "### Deviations from Research" header (body can be "None")
#
# Files Modified and Adjacent card context are NOT checked. Per §5's
# per-card commit discipline, the diff lives in git (`git show <sha>`,
# `git log --grep="#<card>"`) — re-typing it in the comment is bytes
# without signal. §6 dropped both sections accordingly. If they appear in
# a comment they're ignored; if they don't, no error is raised.
#
# Placeholder detection: bullets containing <...> patterns. The §6
# template uses angle-bracketed placeholders like `<path/to/file>` and
# `<happy path>`. A real entry — `apps/web/foo.ts — added auth` — has no
# angle brackets, so it survives the filter; an unfilled template line
# does not.
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
# Fails open (allow) if:
#   - jq or curl missing
#   - env vars missing
#   - card or list lookup fails (network/auth)
#
# The fail-open posture mirrors the other gate hooks: a transient API
# blip should not block legitimate work. The constraint also lives in
# prose (Dev_Protocol.md §5 + §6) so the agent can self-enforce when the
# hook can't.

# Requires-Path: ../board/board.sh
# Board-Actions: move

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# The board layer: tool names, board calls and the column rule.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
if [[ "$HOOK_ACTION" != "move" ]]; then
  exit 0
fi

card_id="$HOOK_CARD_ID"
dest_list_id="$HOOK_DEST_STAGE_ID"
[[ -z "$card_id" || -z "$dest_list_id" ]] && exit 0

board_credentials_present || exit 0

# Resolve the destination column name. Only fire when moving INTO the QA
# column — moves to Now, Done, or anywhere else are out of scope for this
# hook. The column is found with the board layer's column rule, so "QA",
# "QA/QC" and "Ready for QA" all count.
board_stage_get list "$dest_list_id"
dest_list_name=""
if [[ -n "$list" ]]; then
  dest_list_name=$(printf '%s' "$list" | jq -r '.name // empty')
fi

[[ -z "$dest_list_name" ]] && exit 0

board_column_is "$dest_list_name" qa || exit 0

# Fetch the card name (for the error message).
board_card_get card "$card_id"
card_name=""
if [[ -n "$card" ]]; then
  card_name=$(printf '%s' "$card" | jq -r '.title // empty')
fi

# Card lookup failed: fail open.
[[ -z "$card_name" ]] && exit 0

# Fetch the most-recent comment on the card. The latest comment when Dev
# moves Now → Ready for QA should be the Implementation Notes Dev just
# posted. If there are no comments at all, that itself is a fail (the
# artifact is missing).
board_card_notes actions "$card_id" 1
actions="${actions:-[]}"
comment_text=$(echo "$actions" | jq -r '.[0].text // empty')

if [[ -z "$comment_text" ]]; then
  cat >&2 <<EOF
BLOCKED: card "${card_name}" cannot move to Ready for QA — no comments on the card.

Implementation Notes per Dev_Protocol.md §6 must be posted as a comment
before moving the card to Ready for QA. The latest comment is what QA
reads on intake.

Post the §6 template via mcp__trello__add_comment, then retry the move.
EOF
  exit 2
fi

# Helper: extract a section's body (lines after `### Header`, up to the
# next subsection/top-level header or EOF).
extract_section() {
  local section_header="$1"
  printf "%s\n" "$comment_text" | awk -v hdr="$section_header" '
    $0 == hdr { flag = 1; next }
    flag && (/^### / || /^## /) { flag = 0 }
    flag
  '
}

# Helper: count lines matching `pattern` that do NOT contain a `<...>`
# placeholder.
count_real_lines() {
  local body="$1"
  local pattern="$2"
  printf "%s\n" "$body" | grep -E "$pattern" | grep -cv '<[^>]*>' || true
}

errors=()

# 1. Top-level "## Implementation Notes" header.
if ! printf "%s\n" "$comment_text" | grep -qE '^## Implementation Notes'; then
  errors+=("missing top-level '## Implementation Notes' header")
fi

# 2. Services Used — required, ≥ 1 non-placeholder bullet.
if ! printf "%s\n" "$comment_text" | grep -qE '^### Services Used'; then
  errors+=("missing '### Services Used' subsection")
else
  body=$(extract_section "### Services Used")
  count=$(count_real_lines "$body" '^- ')
  if [[ "$count" -lt 1 ]]; then
    errors+=("'### Services Used' has no real bullets (template placeholders only)")
  fi
fi

# 3. Testing Done — required, ≥ 1 non-placeholder "- [x]" line.
if ! printf "%s\n" "$comment_text" | grep -qE '^### Testing Done'; then
  errors+=("missing '### Testing Done' subsection")
else
  body=$(extract_section "### Testing Done")
  count=$(count_real_lines "$body" '^- \[x\]')
  if [[ "$count" -lt 1 ]]; then
    errors+=("'### Testing Done' has no completed checkboxes that aren't template placeholders")
  fi
fi

# 4. Deviations from Research — required header; body can be "None".
if ! printf "%s\n" "$comment_text" | grep -qE '^### Deviations from Research'; then
  errors+=("missing '### Deviations from Research' subsection")
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  cat >&2 <<EOF
BLOCKED: card "${card_name}" cannot move to Ready for QA — Implementation Notes incomplete.

Handing off to QA without a complete artifact wastes the review cycle and
lets §5 Definition of Done violations slip through unflagged. The §6
template exists so QA can audit your work against a known structure;
without it, the diff has to be reverse-engineered for scope, services,
and tests.

Issues found in latest comment on this card:
EOF
  for e in "${errors[@]}"; do
    echo "  - $e" >&2
  done
  cat >&2 <<EOF

Add the missing or unfilled sections per Dev_Protocol.md §5 (Definition of
Done) and §6 (Card Update Format), then post a fresh Implementation Notes
comment via mcp__trello__add_comment and retry the move. If a section
truly does not apply (e.g., no deviations from research), put a literal
"None" in the body — that's content, not a placeholder.
EOF
  exit 2
fi

exit 0
