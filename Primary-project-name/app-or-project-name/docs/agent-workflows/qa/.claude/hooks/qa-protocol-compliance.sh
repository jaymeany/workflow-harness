#!/bin/bash
#
# qa-protocol-compliance.sh — Claude Code PreToolUse hook
#
# Pure-logic backstop ensuring QA applied its protocol to a card before
# moving it out of "QA". Fires on the board's move tool when the card's
# source column is QA. Checks the latest QA comment on the card for the
# structured template defined in QA_Decisions.md §9.
#
# Destination semantics:
#   Done             → expects Status: PASS + all required section headers
#                      present + no individual section marked FAIL
#   Now              → expects Status: FAIL + Required Fixes section
#                      populated
#   Research → expects Status: BOUNCE + non-template Bounce Reason
#                       body. Used when the spec itself is broken (ambiguous
#                       acceptance criteria, missing paired surface, missing
#                       lift source) and Dev cannot meet it as written. See
#                       QA_Decisions.md §8 "Bounce vs. FAIL".
#   Design   → expects Status: BOUNCE + non-template Bounce Reason
#                       body. Used when the gap is in the design of the
#                       surface.
#
# Side effects (pre-move):
#   On FAIL → Now: applies the board's "QA fail" label to the card.
#   On PASS → Done: removes the "QA fail" label (if previously applied)
#                   AND applies the "QA complete" label (creating it on the
#                   board if absent).
#   On BOUNCE → Research: removes the "Research complete" label (if present)
#                   AND applies the "Needs research" label (creating it if
#                   absent). A bounce means the spec is unworkable, so the
#                   card's "Research complete" assertion is now false — it
#                   must not keep claiming finished research while it sits
#                   queued for re-spec.
#   The board adapter decides how each label is found. On Trello, labels are
#   matched by color: red for QA fail, purple for QA complete, green for
#   Research complete, blue for Needs research.
#   All label operations are non-fatal — failures print a warning via
#   additionalContext but the move proceeds.
#
# Post-move behaviors (remaining-queue surface) live in a separate
# PostToolUse hook, qa-post-move.sh — firing after the move has actually
# completed is the right place to advertise "what's next".
#
# Output channels:
#   Blocking decisions (exit 2): stderr as the block reason — Claude Code
#     surfaces this to the model as the failure message.
#   Non-blocking info (exit 0): STDOUT as a JSON object with
#     hookSpecificOutput.additionalContext. Plain stderr on exit 0 is
#     discarded by Claude Code (see hooks docs). Label warnings use this
#     channel.
#
# Does NOT run builds, type-check, or tests. Those are part of QA's protocol
# — QA runs them manually as described in QA_Checks.md §0. This hook only
# enforces that QA documented the result on the card.
#
# Matcher in settings.json: the board's move tool.
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
# Requires-Path: ../board/board.sh
# Board-Actions: move
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message

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
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

board_credentials_present || exit 0

# Fetch the card's current (source) column id + board id.
board_card_get card "$card_id"
source_list_id=""
if [[ -n "$card" ]]; then
  source_list_id=$(printf '%s' "$card" | jq -r '.stage_id // empty')
fi

if [[ -z "$source_list_id" ]]; then
  exit 0
fi

# Resolve column names instead of hardcoded IDs so the hook ports across
# projects and boards that share the same column naming convention.
resolve_list_name() {
  local list_id="$1" list=""
  board_stage_get list "$list_id"
  if [[ -n "$list" ]]; then
    printf '%s' "$list" | jq -r '.name // empty'
  fi
}

source_list_name=$(resolve_list_name "$source_list_id")
dest_list_name=$(resolve_list_name "$dest_list_id")

# Only gate moves originating from "QA".
if ! board_column_is "$source_list_name" qa; then
  exit 0
fi

# Determine expected status based on destination column name.
if board_column_is "$dest_list_name" done; then
  expected_status="PASS"
  dest_name="Done"
elif board_column_is "$dest_list_name" now; then
  expected_status="FAIL"
  dest_name="Now"
elif board_column_is "$dest_list_name" research; then
  expected_status="BOUNCE"
  dest_name="Research"
elif board_column_is "$dest_list_name" design; then
  expected_status="BOUNCE"
  dest_name="Design"
else
  cat >&2 <<EOF
BLOCKED: unexpected destination from "QA".

QA's only legitimate destinations from QA are:
  - "Done"              (on PASS)
  - "Now"               (on FAIL, back to Dev for rework)
  - "Research"          (on BOUNCE, back to Research for re-spec)
  - "Design"            (on BOUNCE, back to Design for the surface)

See QA_Decisions.md §8 Decision Matrix.
EOF
  exit 2
fi

# Fetch latest QA Review comment.
board_card_notes comments "$card_id" 50
comments="${comments:-[]}"

qa_text=$(echo "$comments" | jq -r '
  [.[] | select(.text != null and (.text | startswith("## QA Review")))][0].text // empty
')

if [[ -z "$qa_text" ]]; then
  cat >&2 <<EOF
BLOCKED: cannot move card from "QA" — no QA review comment found.

Before moving this card, add a QA review comment matching the template in
QA_Decisions.md §9. The comment must start with "## QA Review" and contain
the required section headers with PASS/FAIL decisions.

Expected destination: $dest_name
Expected status: $expected_status
EOF
  exit 2
fi

# Check **Status** matches destination.
if ! echo "$qa_text" | grep -qE "^\*\*Status\*\*:\s*${expected_status}\b"; then
  cat >&2 <<EOF
BLOCKED: QA comment status does not match destination.

Destination: $dest_name (expects **Status**: $expected_status)
Latest QA comment does not contain "**Status**: $expected_status".

Either fix the comment to reflect the correct status, or move the card to
the destination matching the status in the comment.
EOF
  exit 2
fi

# Accumulator for non-blocking informational messages (queue state + warnings).
# Emitted as a single JSON blob on stdout (hookSpecificOutput.additionalContext)
# at the end of execution. Must NOT be written to stderr on exit 0 — Claude
# Code discards that channel.
INFO_MSGS=""

board_id=""
if [[ -n "$card" ]]; then
  board_id=$(printf '%s' "$card" | jq -r '.board_id // empty')
fi

# For PASS → Done: all required check sections must be present.
if [[ "$expected_status" == "PASS" ]]; then
  # Section presence enforced here; content is for human readers, not
  # gate-validated. The list matches the §9 PASS template in QA_Decisions.md.
  REQUIRED_SECTIONS=(
    "### Run It"
    "### Service Bypass Check"
    "### Security Check"
    "### Evidence Integrity"
    "### Pipeline Invariants"
    "### Error Handling"
    "### Acceptance Criteria"
    "### Tracking Cards Created"
  )

  missing=()
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! echo "$qa_text" | grep -qF "$section"; then
      missing+=("$section")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "BLOCKED: QA comment marked PASS but missing required sections:" >&2
    echo "" >&2
    for m in "${missing[@]}"; do
      echo "  - $m" >&2
    done
    echo "" >&2
    echo "See QA_Decisions.md §9 for the full comment template." >&2
    exit 2
  fi

  # Individual check FAIL contradicts overall PASS. (N/A is allowed — does not block.)
  SECTIONS_WITH_DECISION=(
    "Run It"
    "Service Bypass Check"
    "Security Check"
    "Evidence Integrity"
    "Pipeline Invariants"
    "Error Handling"
    "Acceptance Criteria"
  )

  fails=()
  for section in "${SECTIONS_WITH_DECISION[@]}"; do
    if echo "$qa_text" | grep -qE "^### ${section}:\s*FAIL\b"; then
      fails+=("$section")
    fi
  done

  if [[ ${#fails[@]} -gt 0 ]]; then
    echo "BLOCKED: QA comment Status=PASS but these checks are marked FAIL:" >&2
    echo "" >&2
    for f in "${fails[@]}"; do
      echo "  - $f" >&2
    done
    echo "" >&2
    echo "Fix the failing checks before moving to Done, or set **Status**: FAIL and move back to Now." >&2
    exit 2
  fi

  # Label operations on PASS → Done. Non-fatal: warnings accumulate into
  # INFO_MSGS and emit at the end. A failed label lookup counts as no labels.
  if [[ -n "$board_id" ]]; then
    board_labels labels "$board_id"
    labels="${labels:-[]}"

    # 1. Clear the QA fail label if previously applied (e.g., from a prior FAIL bounce).
    board_state_label_pick red_label_id "$labels" qa_fail
    if [[ -n "$red_label_id" ]]; then
      board_card_label_remove "$card_id" "$red_label_id"
    fi

    # 2. Apply the "QA complete" label. Create remains a fallback for a board
    #    with no such label at all.
    board_state_label_pick qa_complete_label_id "$labels" qa_complete
    if [[ -z "$qa_complete_label_id" ]]; then
      board_label_create qa_complete_label_id "$board_id" qa_complete
    fi
    if [[ -n "$qa_complete_label_id" ]]; then
      board_card_label_add "$card_id" "$qa_complete_label_id"
      if [[ "$BOARD_STATUS" != "ok" ]]; then
        INFO_MSGS+="WARNING: could not apply QA complete label to card ${card_id}; move allowed."$'\n'
      fi
    else
      INFO_MSGS+="WARNING: could not resolve/create purple QA complete label on board ${board_id}; move allowed without tag."$'\n'
    fi
  fi
fi

# For FAIL → Now: Required Fixes section must be present.
if [[ "$expected_status" == "FAIL" ]]; then
  if ! echo "$qa_text" | grep -qE "^### Required Fixes"; then
    cat >&2 <<EOF
BLOCKED: QA comment marked FAIL but missing Required Fixes section.

Before bouncing this card back to Now, add a "### Required Fixes" section
to the QA comment listing each issue with file:line references.

See QA_Decisions.md §9.
EOF
    exit 2
  fi

  # Tag the failed card with the board's QA fail label. Non-fatal.
  if [[ -n "$board_id" ]]; then
    board_labels labels "$board_id"
    labels="${labels:-[]}"
    board_state_label_pick red_label_id "$labels" qa_fail
    if [[ -n "$red_label_id" ]]; then
      board_card_label_add "$card_id" "$red_label_id"
      if [[ "$BOARD_STATUS" != "ok" ]]; then
        INFO_MSGS+="WARNING: could not apply red label to card ${card_id}; move allowed."$'\n'
      fi
    else
      INFO_MSGS+="WARNING: no red label found on board ${board_id}; card moved without tag."$'\n'
    fi
  else
    INFO_MSGS+="WARNING: could not resolve board id for card ${card_id}; move allowed without tag."$'\n'
  fi
fi

# For BOUNCE → Research or Design: Bounce Reason section must be present
# AND have a non-template body. The §9 template uses a single bracketed
# placeholder line ("[Required, non-template prose. Explain ...]") that
# we strip before checking — an unmodified template should NOT satisfy
# the gate. Real bounce reasoning starts with prose, a "- " bullet, or
# a numbered list item, not "[".
if [[ "$expected_status" == "BOUNCE" ]]; then
  if ! echo "$qa_text" | grep -qE "^### Bounce Reason"; then
    cat >&2 <<EOF
BLOCKED: QA comment marked BOUNCE but missing Bounce Reason section.

Before bouncing this card to "${dest_name}", add a "### Bounce Reason"
section explaining the gap. A bounce to Research means the spec, not the
implementation, is unworkable. A bounce to Design means the gap is in the
design of the surface.

Examples of valid bounce reasons:
  - "Acceptance criteria require an Archive button but no Show Archived
    surface is specced; QA cannot verify a half-loop."
  - "Lift-and-shift card #N references an upstream symbol X which does
    not exist at the cited path."
  - "Acceptance criterion 3 contradicts what shipped in #M (Done)."

See QA_Decisions.md §9 BOUNCE variant.
EOF
    exit 2
  fi

  # Strip "[ ... ]" placeholder lines from the §9 template so an unmodified
  # template body does NOT satisfy the gate.
  bounce_body=$(echo "$qa_text" | awk '
    /^### Bounce Reason/ { flag = 1; next }
    /^### / { flag = 0 }
    flag
  ' | grep -v '^[[:space:]]*\[' | grep -v '^[[:space:]]*-[[:space:]]*\[' | grep -v '^[[:space:]]*$')

  if [[ -z "$bounce_body" ]]; then
    cat >&2 <<'EOF'
BLOCKED: Bounce Reason section is empty or contains only the §9 template
placeholder ("[Required, non-template prose. ...]").

A bounce is a routing decision — the role the card goes back to needs to
know what to fix before Dev can re-attempt. Provide concrete prose explaining
the gap. See QA_Decisions.md §9 BOUNCE variant for examples.
EOF
    exit 2
  fi

  # Label operations on BOUNCE → Research only. A bounce to Design changes no
  # labels; the destination column is the routing signal.
  # For a bounce to Research, the label must not contradict the column: the
  # spec — not the implementation — is unworkable, so the card's "Research
  # complete" assertion is now false and comes off, and "Needs research" goes
  # on. This mirrors FAIL → QA fail and PASS → QA complete.
  # Non-fatal — warnings accumulate.
  if [[ -n "$board_id" && "$dest_name" == "Research" ]]; then
    board_labels labels "$board_id"
    labels="${labels:-[]}"

    # 1. Remove the "Research complete" label if present.
    board_state_label_pick research_complete_label_id "$labels" research_complete
    if [[ -n "$research_complete_label_id" ]]; then
      board_card_label_remove "$card_id" "$research_complete_label_id"
    fi

    # 2. Apply the "Needs research" label. Create remains a fallback for a
    #    board with no such label at all.
    board_state_label_pick needs_research_label_id "$labels" needs_research
    if [[ -z "$needs_research_label_id" ]]; then
      board_label_create needs_research_label_id "$board_id" needs_research
    fi
    if [[ -n "$needs_research_label_id" ]]; then
      board_card_label_add "$card_id" "$needs_research_label_id"
      if [[ "$BOARD_STATUS" != "ok" ]]; then
        INFO_MSGS+="WARNING: could not apply Needs research label to card ${card_id}; move allowed."$'\n'
      fi
    else
      INFO_MSGS+="WARNING: could not resolve/create blue Needs research label on board ${board_id}; move allowed without tag."$'\n'
    fi
  fi
fi

# Queue surface is a PostToolUse concern now; see qa-post-move.sh.

# Emit accumulated info via structured hook output.
# This is the only reliable channel for non-blocking info to reach the model
# on exit 0; plain stderr is discarded by Claude Code.
if [[ -n "$INFO_MSGS" ]]; then
  hook_emit_context PreToolUse "$INFO_MSGS" allow
fi

exit 0
