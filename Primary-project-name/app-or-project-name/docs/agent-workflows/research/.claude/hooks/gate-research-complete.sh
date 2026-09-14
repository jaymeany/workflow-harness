#!/bin/bash
#
# gate-research-complete.sh — Claude Code PreToolUse hook
#
# Three responsibilities:
#
# 1. On `mcp__trello__move_card` to a "Now" list: verify the card has a
#    "## Research Complete" marker and no unresolved blockers. Block the
#    move if the gate fails. Attach a green "Research complete" label on
#    pass.
#
# 2. On `mcp__trello__update_card_details` where the new description
#    qualifies as research-complete (marker present, no blocker tags, no
#    unresolved `## Open Questions`): attach the green "Research complete"
#    label so the card is visually marked on the board. Never blocks — the
#    label-on-save path is best-effort.
#
# 3. On `mcp__trello__update_card_details` where `tool_input.labels`
#    includes the Research-complete label id: deny the update if the
#    post-update description does not qualify. Closes the bypass where an
#    agent attaches the label directly via the labels field instead of
#    earning it through the description.
#
# Matcher in settings.json: "mcp__trello__(move_card|update_card_details)"
#
# Environment:
#   TRELLO_API_KEY — required
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required (either name accepted)
#
# Requires: jq, curl
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message (move_card gate only)

set -euo pipefail

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# Shared helpers: evaluate_research_complete, attach_research_complete_label,
# find_research_complete_label_id. See lib.sh for criteria + behavior.
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

case "$tool_name" in
  mcp__trello__move_card|mcp__trello__update_card_details) ;;
  *) exit 0 ;;
esac

TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]]; then
  exit 0
fi

# ============================================================================
# Flow A: update_card_details
#
# Two enforcement roles:
#   1. Deny any update that tries to attach the green "Research complete" label
#      to a card whose (post-update) description does NOT qualify as
#      research-complete. Prevents bypassing the gate by manually setting
#      tool_input.labels = [research_complete_label_id].
#   2. When a description is being set AND qualifies, auto-attach the label
#      (non-blocking label-on-save).
# ============================================================================

if [[ "$tool_name" == "mcp__trello__update_card_details" ]]; then
  card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
  if [[ -z "$card_id" ]]; then
    exit 0
  fi

  new_desc=$(echo "$input" | jq -r '.tool_input.description // empty')
  has_desc_update=0
  [[ -n "$new_desc" ]] && has_desc_update=1

  # Lookup the board-level green "Research complete" label id for this card's board.
  board_id=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idBoard&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null | jq -r '.idBoard // empty')
  research_label_id=""
  if [[ -n "$board_id" ]]; then
    research_label_id=$(find_research_complete_label_id "$board_id")
  fi

  # Does tool_input.labels (if present) include the Research Complete label id?
  adding_research_label=0
  if [[ -n "$research_label_id" ]]; then
    labels_in_input=$(echo "$input" | jq -r --arg rid "$research_label_id" '(.tool_input.labels // []) | index($rid) // empty')
    if [[ -n "$labels_in_input" ]]; then
      adding_research_label=1
    fi
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
  # gate-card-structure (it now also checks the required sections), so a card
  # that another gate would reject on structure also fails here — no split-brain.
  desc_to_check="$new_desc"
  if [[ "$has_desc_update" == "0" ]]; then
    current=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=desc&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
    desc_to_check=$(echo "$current" | jq -r '.desc // empty')
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

  # Qualifies: advance Research's column -> "Now". The tool call then attaches
  # the label. This hook is registered LAST among PreToolUse entries, so
  # gate-column-scope has already confirmed the card is in Research's column
  # and passed; no later hook can deny this call, so the advance is safe.
  advance_card_to_now "$card_id"
  exit 0
fi

# ============================================================================
# Flow B: move_card — gate enforcement + label on pass
# ============================================================================

card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
dest_list_id=$(echo "$input" | jq -r '.tool_input.listId // empty')
if [[ -z "$card_id" || -z "$dest_list_id" ]]; then
  exit 0
fi

# Only gate moves to a list named "Now" (case-insensitive). Matching by
# name instead of hardcoded ID so the hook works across the main board
# and any feature-worktree boards that share the same column naming.
dest_list=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${dest_list_id}?fields=name&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '{}')
dest_name=$(echo "$dest_list" | jq -r '.name // empty')
if [[ -z "$dest_name" ]]; then
  exit 0
fi
if ! echo "$dest_name" | grep -qiE '^now$'; then
  exit 0
fi

# Fetch the card's current description.
card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=desc&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" || echo '{}')
desc=$(echo "$card" | jq -r '.desc // empty')
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
