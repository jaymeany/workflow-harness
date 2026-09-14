#!/bin/bash
#
# qa-pass-evidence-gate.sh — Claude Code PreToolUse hook on
# mcp__trello__move_card.
#
# Catches the rubber-stamp PASS: QA reads a diff, sees it compiles and
# looks plausible, and moves the card to Done without ever confirming the
# card's actual deliverable EXISTS and FUNCTIONS. The failure shape: a card
# PASSes with the code that selects a record shipped, while the records it
# selects exist nowhere. The diff is green; the feature is broken.
#
# The gate forces the PASS comment to SHOW its verification work. Every
# PASS → Done move must carry a "### Verification" section containing at
# least one piece of runtime/existence evidence — a command actually run,
# a portal the surface was rendered in, or a row/path confirmed to exist —
# OR an explicit, justified N/A for cards with no runtime surface.
#
# Crucially, a bare file:line citation does NOT satisfy the gate. Dressing
# code-reading in `:line` references and calling it verified is exactly the
# loophole that ships a green diff over a broken feature. Citations are not
# verification. The evidence must be an observation/command, not a pointer.
#
# Two escape hatches keep a legitimate PASS from ever being cornered:
#   1. Justified N/A — a card with genuinely nothing to run (pure refactor,
#      copy-only, config) PASSes by writing why there's no runtime surface
#      (e.g. "N/A — no runtime surface; verified by type-check + grep").
#      Articulable, on the record — not a bypass token.
#   2. Fail-open on missing jq/curl/env, same posture as the sibling gates.
#
# Algorithm:
#   1. Only fire on move_card from "QA" → "Done".
#   2. Read the latest "## QA Review" comment. Only gate Status: PASS
#      (FAIL → Now and BOUNCE → Research carry no Done deliverable).
#   3. Require a "### Verification" section. Extract its body (up to the
#      next "### " boundary), drop pure-placeholder lines.
#   4. Allow if the body shows runtime/existence evidence OR a justified
#      N/A. Otherwise deny — citations alone are not evidence.
#
# Companion to qa-protocol-compliance.sh (template format / destination
# match) and qa-required-fixes-coverage.sh (iteration-N fix continuity).
# All three fire on the same move_card trigger; order is irrelevant.
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

# Source list filter — only QA.
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

# Destination filter — only Done. FAIL/BOUNCE moves carry no Done deliverable.
dest_list_name=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${dest_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null \
  | jq -r '.name // empty' \
  | tr '[:upper:]' '[:lower:]')

if ! printf '%s' "$dest_list_name" | grep -qiE '(^|[^[:alnum:]])done([^[:alnum:]]|$)'; then
  exit 0
fi

# Pull QA review comments, newest first.
comments=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}/actions?filter=commentCard&limit=50&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '[]')

latest_qa=$(echo "$comments" | jq -r '
  [.[] | select(.data.text != null and (.data.text | startswith("## QA Review")))][0].data.text // empty
')

if [[ -z "$latest_qa" ]]; then
  # No QA review at all — protocol-compliance hook will catch this. Pass.
  exit 0
fi

# Only gate PASS. FAIL/BOUNCE carry no Done deliverable to verify.
if ! echo "$latest_qa" | grep -qE '\*\*Status\*\*:[[:space:]]*PASS'; then
  exit 0
fi

# Extract the "### Verification" section body, up to the next "### " heading.
verification_body=$(echo "$latest_qa" | awk '
  /^### Verification([[:space:]:]|$)/ { flag = 1; next }
  /^### / { flag = 0 }
  flag
')

# Drop pure-placeholder lines: bracket-only template stubs like "- [Details]"
# or "[Evidence]" contribute nothing. Keep substantive prose.
verification_clean=$(echo "$verification_body" \
  | grep -vE '^[[:space:]]*-?[[:space:]]*\[[^]]*\][[:space:]]*$' \
  | grep -vE '^[[:space:]]*$' || true)

if [[ -z "$verification_clean" ]]; then
  cat >&2 <<'EOF'
BLOCKED: PASS → Done is missing a non-empty "### Verification" section.

A PASS must SHOW that the card's deliverable exists and functions — not just
that the diff compiles. Add a "### Verification" section to the QA review
comment with at least one piece of runtime/existence evidence:

  ### Verification
  - Ran `npx vitest run <path>` — 88/88 passed
  - Confirmed the new row exists in the seed file
  - Rendered the new tab in the running app (Playwright) — visible, populated

A bare file:line citation does NOT count — that's code-reading, not
verification.

Escape hatch for cards with no runtime surface (pure refactor, copy-only,
config): write a justified N/A, e.g.
  ### Verification
  - N/A — no runtime surface; verified by type-check + grep of call sites.

If you cannot produce either, you have not verified the deliverable — that
is FAIL → Now, not PASS → Done.
EOF
  exit 2
fi

# Runtime/existence evidence: a command run, a surface rendered, a row/path
# confirmed. Deliberately broad on phrasing, but requires an observation or
# command verb — NOT a bare path:line, which matches none of these.
EVIDENCE_RE='(^|[^a-zA-Z])(ran|run|rendered|render|renders|loaded|navigated|clicked|screenshot|browser|playwright|grep|grepped|ripgrep|rg|vitest|npx|npm run|pnpm|yarn|psql|queried|query|seeded|seed (file|script)|confirmed|observed|reproduced|exists at|present at|in the [a-z]+ portal|storybook)([^a-zA-Z]|$)'

# Justified-N/A path: an explicit no-runtime-surface declaration. Require a
# justification keyword alongside the N/A so it is not a bare bypass word.
NA_DECL_RE='(n/?a|no runtime surface|nothing to run|no behavioral surface)'
NA_REASON_RE='(type-?check|lint|grep|reason|refactor|copy[- ]only|doc(s|umentation)?|config|rename|comment[- ]only|verified)'

if echo "$verification_clean" | grep -qiE "$EVIDENCE_RE"; then
  exit 0
fi

if echo "$verification_clean" | grep -qiE "$NA_DECL_RE" \
   && echo "$verification_clean" | grep -qiE "$NA_REASON_RE"; then
  exit 0
fi

cat >&2 <<'EOF'
BLOCKED: "### Verification" section shows no runtime/existence evidence.

The section is present but contains no proof the deliverable exists and
functions — only assertions or file:line citations. Citations are pointers,
not verification.

Provide at least ONE of:
  - a command you actually ran (`npx vitest run …`, `grep …`, `psql …`)
    and its result,
  - a portal/surface you rendered the deliverable in (admin/employer/…
    portal, Storybook, Playwright) and what you saw,
  - a row or file you confirmed exists.

Or, for a card with genuinely no runtime surface, a justified N/A:
  - N/A — no runtime surface; verified by type-check + grep.

If you can't produce either, the deliverable isn't verified → FAIL → Now.
EOF
exit 2
