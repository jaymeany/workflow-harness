#!/bin/bash
#
# lib.sh — shared helpers for Research-instance hooks
#
# Sourced by:
#   - gate-research-complete.sh
#   - apply-research-complete-label.sh
#
# Both hooks need the same two operations: deciding whether a description
# qualifies as research-complete, and attaching the "Research complete" label
# to a card. Keeping these in one place prevents the criteria from drifting
# between create-time (apply-research-complete-label.sh) and update/move-time
# (gate-research-complete.sh).
#
# Board access goes through the board layer (../../../board/board.sh), which
# this file loads. Callers check BOARD_LOADED after sourcing.
#
# This file is sourced, not executed — no shebang behavior is invoked, but
# the line is kept so editors syntax-highlight as bash and bash -n works.
#
# Required by callers:
#   - bash >= 3.2 (macOS /bin/bash compatible)
#   - jq, curl on PATH (callers exit 0 if missing; lib does not re-check)
#
# All functions are pure with respect to caller state — they do not modify
# globals, only echo or perform side-effectful board calls.

if [[ "${BOARD_LOADED:-}" != "1" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../../../board/board.sh" 2>/dev/null || true
fi

# ============================================================================
# evaluate_research_complete <description>
#
# Echoes a status string identifying whether the description qualifies as
# research-complete. Never blocks; pure function.
#
# Status values:
#   ok                         — qualifies
#   empty_desc                 — description is empty
#   missing_marker             — no "## Research Complete" header
#   needs_user_approval        — contains "[Needs User Approval]"
#   needs_clarification        — contains "[Needs Clarification]"
#   unresolved_open_questions  — "## Open Questions" header with unresolved body
#   missing_required_sections  — marker present but a required section is absent
#                                (mirrors gate-card-structure.sh Check C:
#                                Services Discovered/Verified gap, Files/Acceptance,
#                                Confidence). Keeps the two gates aligned so a
#                                structurally-incomplete card is never judged "ok".
#
# Open-questions detection: triggers on the EXACT section header
# "^## Open Questions$" (trailing whitespace tolerated) UNLESS the description
# also contains a sibling "^## Open Questions (Resolved)$" header. The
# resolved sibling is how a card transitions out of "unresolved" state under
# the append-only description constraint — the lead cannot remove or rename
# the original section, so the resolution is signaled by an additional
# header lower in the document that lists each original question with its
# answer. The header itself is the signal — bullet content is not inspected.
# Rationale: bullets within the Open Questions section are commonly used for
# non-question content (references, notes, partial-resolution annotations),
# so a body-content check would generate false positives and erode the gate's
# authority.
#
# Resolution paths (any of):
#   - Delete the section entirely (only possible via user-authorized
#     wholesale description overwrite)
#   - Rename the section to anything other than the exact title (only via
#     wholesale overwrite for the same reason)
#   - Append a "## Open Questions (Resolved)" section to the description
#     with the per-question resolutions (the canonical append-only path)
#   - Add a "[Needs User Approval]" tag to escalate (separate status)
# ============================================================================
evaluate_research_complete() {
  local desc="$1"
  if [[ -z "$desc" ]]; then
    echo "empty_desc"
    return
  fi
  if ! echo "$desc" | grep -qE '^## Research Complete'; then
    echo "missing_marker"
    return
  fi
  if echo "$desc" | grep -qE '\[Needs User Approval\]'; then
    echo "needs_user_approval"
    return
  fi
  if echo "$desc" | grep -qE '\[Needs Clarification\]'; then
    echo "needs_clarification"
    return
  fi
  if echo "$desc" | grep -qE '^## Open Questions[[:space:]]*$'; then
    # Content-aware: extract the body under "## Open Questions" (everything
    # until the next "## " header or EOF) and treat it as resolved when the
    # body is empty or a no-questions sentinel ("None", "None.", "N/A", dash).
    # Only block when there's actual unresolved content. Rationale: the gate
    # is named for questions, not headers — "## Open Questions\n\nNone." is
    # the protocol-canonical way to say "no questions" and must not trap.
    open_q_body=$(printf '%s\n' "$desc" | awk '
      /^## Open Questions[[:space:]]*$/ { capture = 1; next }
      /^## / { capture = 0 }
      capture { print }
    ')
    normalized=$(printf '%s' "$open_q_body" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if ! [[ "$normalized" =~ ^(none\.?|n/a|\(none\)|—|-)?$ ]]; then
      # Actual content under the header — allow only if a sibling "(Resolved)"
      # header exists (legacy append-only resolution path).
      if ! echo "$desc" | grep -qE '^## Open Questions \(Resolved\)[[:space:]]*$'; then
        echo "unresolved_open_questions"
        return
      fi
    fi
  fi
  # Structural completeness — mirror gate-card-structure.sh Check C so the two
  # gates AGREE on what "research-complete" means. Without this, a description
  # that declares the marker but omits a required section is blocked by
  # gate-card-structure.sh (the write is rejected) while this evaluator still
  # returns "ok" — so a sibling hook's label/advance side effects fire on a
  # write that never landed, stranding a mislabeled card in Dev's column with a
  # stale description. Requiring the same sections here keeps the gates aligned:
  # an incomplete card is "incomplete", not "ok".
  local _conf_file
  _conf_file="$(dirname "${BASH_SOURCE[0]}")/protocol-enforcement.conf"
  if [[ -f "$_conf_file" ]]; then
    # shellcheck disable=SC1090
    source "$_conf_file"
    if [[ -n "${REQUIRED_WHEN_RESEARCH_COMPLETE[*]:-}" ]]; then
      local _slot _alt _slot_ok
      for _slot in "${REQUIRED_WHEN_RESEARCH_COMPLETE[@]}"; do
        _slot_ok=0
        IFS='|' read -ra _alts <<< "$_slot"
        for _alt in "${_alts[@]}"; do
          if printf '%s\n' "$desc" | grep -qE "^## ${_alt}([[:space:]]|\$|\()"; then
            _slot_ok=1
            break
          fi
        done
        if [[ "$_slot_ok" == "0" ]]; then
          echo "missing_required_sections"
          return
        fi
      done
    fi
  fi
  echo "ok"
}

# ============================================================================
# attach_research_complete_label <card_id>
#
# Best-effort: looks up the card's board, finds (or creates) the board's
# "Research complete" label, and attaches it to the card. The board adapter
# decides how that label is found; on Trello it is the green label, matched by
# color only. Idempotent — the board ignores duplicate label attachments.
#
# A failed label lookup counts as "no label", so the label is created.
#
# Always returns 0. Failures (network, missing board, label-create denied)
# are swallowed because label attachment is decoration, not enforcement.
# ============================================================================
attach_research_complete_label() {
  local card_id="$1" card="" board_id="" labels="" label_id=""
  board_credentials_present || return 0

  board_card_get card "$card_id"
  [[ -n "$card" ]] || return 0
  board_id=$(printf '%s' "$card" | jq -r '.board_id // empty' 2>/dev/null || echo "")
  [[ -n "$board_id" ]] || return 0

  board_labels labels "$board_id"
  board_state_label_pick label_id "${labels:-[]}" research_complete
  if [[ -z "$label_id" ]]; then
    board_label_create label_id "$board_id" research_complete
  fi
  [[ -n "$label_id" ]] || return 0

  board_card_label_add "$card_id" "$label_id"
  return 0
}

# ============================================================================
# advance_card_to_now <card_id>
#
# If the card is currently in Research's column, move it to the same
# board's "Now" column. Best-effort — silent on failure. Idempotent: a card
# already outside Research's column is unchanged.
#
# Why this exists: research-complete is a transition state, not just a
# label. When a card crosses the bar (lead's update, QA-card review, or
# create-time post-attach), the workflow promotes it to Dev's column
# automatically. The lead doesn't issue an explicit move_card; reaching
# research-complete IS the handoff signal. Companion to
# attach_research_complete_label; called from the same `ok` paths.
#
# Columns are found by name, with the board layer's column rule.
#
# Always returns 0. Failures (network, missing column, API denial) are
# swallowed so the auto-advance behavior never blocks the calling hook.
# ============================================================================
advance_card_to_now() {
  local card_id="$1" card="" id_list="" id_board="" list="" current_name="" lists="" now_list_id=""
  board_credentials_present || return 0

  # Fetch the card's current column and board.
  board_card_get card "$card_id"
  [[ -n "$card" ]] || return 0
  id_list=$(printf '%s' "$card" | jq -r '.stage_id // empty' 2>/dev/null || echo "")
  id_board=$(printf '%s' "$card" | jq -r '.board_id // empty' 2>/dev/null || echo "")
  if [[ -z "$id_list" || -z "$id_board" ]]; then
    return 0
  fi

  # Confirm the card is in Research's column. If not, do not advance.
  board_stage_get list "$id_list"
  if [[ -n "$list" ]]; then
    current_name=$(printf '%s' "$list" | jq -r '.name // empty' 2>/dev/null || echo "")
  fi
  board_column_is "$current_name" research || return 0

  # Find the Now column on the same board.
  board_stages lists "$id_board"
  [[ -n "$lists" ]] || return 0
  now_list_id=$(printf '%s' "$lists" | jq -r --arg re "$(board_column_regex now)" \
    '[.[] | select(.name | test($re; "i"))][0].id // empty' 2>/dev/null || echo "")
  [[ -n "$now_list_id" ]] || return 0

  board_card_move "$card_id" "$now_list_id"
  return 0
}

# ============================================================================
# find_research_complete_label_id <board_id>
#
# Echoes the board's "Research complete" label id, or empty string if the
# label doesn't exist. Used by gate-research-complete.sh to detect the
# "attach via tool_input.labels" bypass attempt.
#
# Does NOT create the label — read-only. Use attach_research_complete_label
# when you actually want to attach (which create-on-miss is part of).
# ============================================================================
find_research_complete_label_id() {
  local board_id="$1" labels="" label_id=""
  board_credentials_present || return 0
  [[ -n "$board_id" ]] || return 0
  board_labels labels "$board_id"
  board_state_label_pick label_id "${labels:-[]}" research_complete
  printf '%s' "$label_id"
}
