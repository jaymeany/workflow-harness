#!/bin/bash
#
# gate-research-complete.sh — Claude Code PreToolUse hook
#
# Two flows:
#
# 1. Update (the canonical handoff). When an update attaches the "Research
#    complete" label, the card must qualify. A qualifying card advances from
#    Research's column to Now; a card that does not qualify is denied. An
#    update that does not attach the label has no side effect.
#
# 2. Move to the Now column: verify the card has a "## Research Complete"
#    marker and no unresolved blockers. Block the move if the gate fails.
#    Attach the "Research complete" label on pass.
#
# Board access, tool names and the column rule come from the board layer,
# loaded through lib.sh.
#
# Matcher in settings.json: the board's move and update tools.
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
# Requires-Path: ../board/board.sh
# Board-Actions: move, update
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# Shared helpers: evaluate_research_complete, attach_research_complete_label,
# find_research_complete_label_id, advance_card_to_now. lib.sh also loads the
# board layer.
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
case "$HOOK_ACTION" in
  move|update) ;;
  *) exit 0 ;;
esac

board_credentials_present || exit 0

# ============================================================================
# Flow A: update
#
# Two enforcement roles:
#   1. Deny any update that tries to attach the "Research complete" label to a
#      card whose (post-update) description does NOT qualify as
#      research-complete. Prevents bypassing the gate by setting the label
#      directly in the update's labels.
#   2. When the card qualifies, advance it to Now.
# ============================================================================

if [[ "$HOOK_ACTION" == "update" ]]; then
  card_id="$HOOK_CARD_ID"
  if [[ -z "$card_id" ]]; then
    exit 0
  fi

  new_desc="$HOOK_DESCRIPTION"
  has_desc_update=0
  [[ -n "$new_desc" ]] && has_desc_update=1

  # Look up the board's "Research complete" label id for this card's board.
  board_card_get card "$card_id"
  board_id=""
  if [[ -n "$card" ]]; then
    board_id=$(printf '%s' "$card" | jq -r '.board_id // empty')
  fi
  research_label_id=""
  if [[ -n "$board_id" ]]; then
    research_label_id=$(find_research_complete_label_id "$board_id")
  fi

  # Do the update's labels include the Research complete label id?
  adding_research_label=0
  if [[ -n "$research_label_id" ]] && printf '%s\n' "$HOOK_LABEL_IDS" | grep -qxF "$research_label_id"; then
    adding_research_label=1
  fi

  # The "Research complete" label is the SINGLE handoff trigger. A content-only
  # update (description and/or name, no label) has NO label or advance side
  # effect — it only edits the card, so a content write can never strand a card
  # mid-handoff. The card advances to "Now" ONLY when this update attaches the
  # label, and only if the card fully qualifies. Validate-then-advance lives in
  # this one block so it is atomic: a non-qualifying card returns at exit 2 and
  # the advance below never runs.
  if [[ "$adding_research_label" == "0" ]]; then
    exit 0
  fi

  # Evaluate the incoming description if this update bundles one, else the
  # card's current description. evaluate_research_complete is unified with
  # gate-card-structure (it also checks the required sections), so a card
  # that another gate would reject on structure also fails here.
  desc_to_check="$new_desc"
  if [[ "$has_desc_update" == "0" ]]; then
    desc_to_check=""
    if [[ -n "$card" ]]; then
      desc_to_check=$(printf '%s' "$card" | jq -r '.description // empty')
    fi
  fi

  status=$(evaluate_research_complete "$desc_to_check")
  if [[ "$status" != "ok" ]]; then
    cat >&2 <<EOF
BLOCKED: cannot attach "Research complete" label — card does not qualify (status: $status).

Attaching this label is the single action that hands the card to Dev (advances
it to "Now"). It is allowed only when the description meets ALL of:
  - "## Research Complete" marker
  - required sections: Services Discovered (or Verified gap), Files (or
    Acceptance), Confidence
  - no "[Needs User Approval]" / "[Needs Clarification]" tag
  - no unresolved "## Open Questions"

Finish the description first (a content-only update has no side effects), then
attach the label.
EOF
    exit 2
  fi

  # Qualifies: advance Research's column to Now. The tool call then attaches
  # the label.
  advance_card_to_now "$card_id"
  exit 0
fi

# ============================================================================
# Flow B: move — gate enforcement + label on pass
# ============================================================================

card_id="$HOOK_CARD_ID"
dest_list_id="$HOOK_DEST_STAGE_ID"
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

# Only gate moves to the Now column, found by name with the column rule.
board_stage_get dest_list "$dest_list_id"
dest_name=""
if [[ -n "$dest_list" ]]; then
  dest_name=$(printf '%s' "$dest_list" | jq -r '.name // empty')
fi
if [[ -z "$dest_name" ]]; then
  exit 0
fi
if ! board_column_is "$dest_name" now; then
  exit 0
fi

# Fetch the card's current description.
board_card_get card "$card_id"
desc=""
if [[ -n "$card" ]]; then
  desc=$(printf '%s' "$card" | jq -r '.description // empty')
fi
status=$(evaluate_research_complete "$desc")

case "$status" in
  empty_desc)
    cat >&2 <<'EOF'
BLOCKED: cannot move card to "Now" — card has no description.

Before moving to Now, the card must contain research findings including:
  - Services discovered (with file paths)
  - Files to modify/create
  - Required services per QA checklist
  - ## Research Complete marker
  - Zero unresolved open questions

See Research_Role.md § Handoff to Dev and
protocol/Research_Protocol.md § Quality checks.
EOF
    exit 2
    ;;
  missing_marker)
    cat >&2 <<'EOF'
BLOCKED: cannot move card to "Now" without "## Research Complete" marker.

Before moving:
  - Ensure all research is documented on the card
  - Resolve all open questions (or escalate to user)
  - Add "## Research Complete" section to the card description

See Research_Role.md § Handoff to Dev.
EOF
    exit 2
    ;;
  needs_user_approval)
    cat >&2 <<'EOF'
BLOCKED: card has "[Needs User Approval]" tag.

Get user approval first, then remove the tag from the card description
before moving to Now.
EOF
    exit 2
    ;;
  needs_clarification)
    cat >&2 <<'EOF'
BLOCKED: card has "[Needs Clarification]" tag.

This tag signals Dev needs Research to re-investigate. Either:
  - Research re-investigates and removes the tag, OR
  - Escalate to the user if the question cannot be answered from code

The card must not return to Now until the tag is cleared.

See Research_Role.md § Tags.
EOF
    exit 2
    ;;
  unresolved_open_questions)
    cat >&2 <<'EOF'
BLOCKED: card has an exact "## Open Questions" section header.

protocol/Research_Protocol.md § Open questions: "Zero open questions before a card
moves to Now. A card with unresolved open questions is not research-complete
regardless of the marker — the gate will block the move."

The gate triggers on the section header alone — bullets inside are not
inspected (they're commonly used for non-question content). To clear:

  - Delete the "## Open Questions" section entirely, OR
  - Rename it to anything else (e.g., "## Open Questions (resolved)",
    "## Resolved Questions", "## Notes"), OR
  - Escalate to the user and mark the card "[Needs User Approval]" — that
    blocks for a different reason but keeps the question visible.
EOF
    exit 2
    ;;
  missing_required_sections)
    cat >&2 <<'EOF'
BLOCKED: cannot move card to "Now" — description declares "## Research Complete"
but is missing a required section.

When the marker is present, the description must also contain:
  - ## Services Discovered (or ## Verified gap)
  - ## Files to Modify / ## Files to Create (or ## Acceptance)
  - ## Confidence

Add the missing section(s). The canonical handoff is to attach the
"Research complete" label (it runs this same check and advances the card);
an explicit move_card is gated identically.
EOF
    exit 2
    ;;
  ok)
    attach_research_complete_label "$card_id"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
