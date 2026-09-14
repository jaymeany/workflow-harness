#!/bin/bash
#
# lib.sh — shared helpers for Research-instance hooks
#
# Sourced by:
#   - gate-research-complete.sh
#   - apply-research-complete-label.sh
#   - gate-column-scope.sh
#   - gate-description-append-only.sh
#
# Both hooks need the same two operations: deciding whether a description
# qualifies as research-complete, and attaching the green "Research complete"
# label to a card. Keeping these in one place prevents the criteria from
# drifting between create-time (apply-research-complete-label.sh) and
# update/move-time (gate-research-complete.sh).
#
# This file is sourced, not executed — no shebang behavior is invoked, but
# the line is kept so editors syntax-highlight as bash and bash -n works.
#
# Required by callers:
#   - bash >= 3.2 (macOS /bin/bash compatible)
#   - jq, curl on PATH (callers exit 0 if missing; lib does not re-check)
#   - TRELLO_API_KEY, TRELLO_API_TOKEN/TRELLO_TOKEN env vars (caller-checked)
#
# All functions are pure with respect to caller state — they do not modify
# globals, only echo or perform side-effectful HTTP calls.

# ============================================================================
# is_research_column <list-name>
#
# True if the list name denotes Research's column. Plain case-insensitive
# SUBSTRING match — any name containing "research" passes: "Research",
# "Research and prep", "Research & Prep", "Researching", "Pre-research".
#
# Deliberately NOT an exact match. The board's column label is cosmetic and
# gets renamed; the role's identity is not. An anchored '^research and prep$'
# meant a one-word relabel silently took the whole role offline: every
# description write denied by gate-column-scope, every handoff advance
# skipped by advance_card_to_now. The column is whichever one says research.
#
# Relaxed from a word-boundary regex to substring. The boundary version excluded "Researcher notes" on purpose,
# but that exclusion protected nothing: there is no plausible column whose
# name contains "research" that is NOT Research's column, so the boundary
# only created new ways for a rename to break the role — the exact failure
# the non-anchored match exists to prevent.
#
# Callers pass a name that may be empty (API failure) — empty returns false,
# and every caller fails open on empty before reaching here.
# ============================================================================
is_research_column() {
  printf '%s' "${1:-}" | grep -qi 'research'
}

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
# Best-effort: looks up the card's board, finds (or creates) a green label
# named "Research complete", and attaches it to the card. Idempotent —
# Trello silently ignores duplicate label attachments.
#
# Always returns 0. Failures (network, missing board, label-create denied)
# are swallowed because label attachment is decoration, not enforcement.
# ============================================================================
attach_research_complete_label() {
  local card_id="$1"
  local trello_token="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
  if [[ -z "${TRELLO_API_KEY:-}" || -z "$trello_token" ]]; then
    return 0
  fi

  local card_json board_id
  card_json=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idBoard&key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '{}')
  board_id=$(echo "$card_json" | jq -r '.idBoard // empty' 2>/dev/null || echo "")
  if [[ -z "$board_id" ]]; then
    return 0
  fi

  # Find the board's green label, or create one if absent.
  #
  # Matched by COLOR ONLY. Label semantics on these boards are carried by the
  # color; every label except green is unnamed, and green's name is one click
  # from being cleared in the Trello UI with no guard. A name predicate that
  # stops matching does not fail loudly here — it falls through to the create
  # branch below and MINTS A DUPLICATE green label, which is the same defect
  # already fixed on QA's purple and blue selectors.
  local labels label_id
  labels=$(curl -s --max-time 5 "https://api.trello.com/1/boards/${board_id}/labels?key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '[]')
  label_id=$(printf '%s' "$labels" | jq -r '.[] | select(.color=="green") | .id' 2>/dev/null | head -n1)
  if [[ -z "$label_id" ]]; then
    local created
    created=$(curl -s --max-time 5 -X POST \
      "https://api.trello.com/1/labels?name=Research%20complete&color=green&idBoard=${board_id}&key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '{}')
    label_id=$(printf '%s' "$created" | jq -r '.id // empty')
  fi
  if [[ -z "$label_id" ]]; then
    return 0
  fi

  curl -s --max-time 5 -X POST \
    "https://api.trello.com/1/cards/${card_id}/idLabels?value=${label_id}&key=${TRELLO_API_KEY}&token=${trello_token}" \
    >/dev/null 2>&1 || true

  return 0
}

# ============================================================================
# advance_card_to_now <card_id>
#
# If the card is currently in Research's column, move it to the same
# board's "Now" list. Best-effort — silent on failure. Idempotent: a card
# already outside Research's column is unchanged.
#
# Why this exists: research-complete is a transition state, not just a
# label. When a card crosses the bar (lead's update, QA-card review, or
# create-time post-attach), the workflow promotes it to Dev's column
# automatically. This is one of the oldest functions in the role layer —
# the lead doesn't issue an explicit move_card; reaching research-complete
# IS the handoff signal. Companion to attach_research_complete_label;
# called from the same `ok` paths.
#
# Match by list name (via is_research_column) rather than ID so the function
# works across the main board and any feature-worktree boards that share
# column naming. Mirrors gate-column-scope.sh's name-match approach.
#
# Always returns 0. Failures (network, missing list, API denial) are
# swallowed so the auto-advance behavior never blocks the calling hook.
# ============================================================================
advance_card_to_now() {
  local card_id="$1"
  local trello_token="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
  if [[ -z "${TRELLO_API_KEY:-}" || -z "$trello_token" ]]; then
    return 0
  fi

  # Fetch the card's current list and board.
  local card_json id_list id_board
  card_json=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=idList,idBoard&key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '{}')
  id_list=$(echo "$card_json" | jq -r '.idList // empty' 2>/dev/null || echo "")
  id_board=$(echo "$card_json" | jq -r '.idBoard // empty' 2>/dev/null || echo "")
  if [[ -z "$id_list" || -z "$id_board" ]]; then
    return 0
  fi

  # Confirm the card is in Research's column. If not, do not advance —
  # the function is a no-op outside that column.
  local current_list_json current_name
  current_list_json=$(curl -s --max-time 5 "https://api.trello.com/1/lists/${id_list}?fields=name&key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '{}')
  current_name=$(echo "$current_list_json" | jq -r '.name // empty' 2>/dev/null || echo "")
  if ! is_research_column "$current_name"; then
    return 0
  fi

  # Find the "Now" list on the same board (case-insensitive name match).
  local lists_json now_list_id
  lists_json=$(curl -s --max-time 5 "https://api.trello.com/1/boards/${id_board}/lists?fields=name&key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '[]')
  now_list_id=$(printf '%s' "$lists_json" | jq -r '.[] | select(.name | ascii_downcase | test("(^|[^a-z0-9])now([^a-z0-9]|$)")) | .id' 2>/dev/null | head -n1)
  if [[ -z "$now_list_id" ]]; then
    return 0
  fi

  # Move the card. Trello accepts PUT /cards/{id}/idList?value=<list-id>.
  curl -s --max-time 5 -X PUT \
    "https://api.trello.com/1/cards/${card_id}/idList?value=${now_list_id}&key=${TRELLO_API_KEY}&token=${trello_token}" \
    >/dev/null 2>&1 || true

  return 0
}

# ============================================================================
# find_research_complete_label_id <board_id>
#
# Echoes the board's green "Research complete" label id, or empty string if
# the label doesn't exist. Used by gate-research-complete.sh to detect the
# "attach via tool_input.labels" bypass attempt.
#
# Does NOT create the label — read-only. Use attach_research_complete_label
# when you actually want to attach (which create-on-miss is part of).
# ============================================================================
find_research_complete_label_id() {
  local board_id="$1"
  local trello_token="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
  if [[ -z "${TRELLO_API_KEY:-}" || -z "$trello_token" || -z "$board_id" ]]; then
    return 0
  fi
  local labels
  labels=$(curl -s --max-time 5 "https://api.trello.com/1/boards/${board_id}/labels?key=${TRELLO_API_KEY}&token=${trello_token}" 2>/dev/null || echo '[]')
  # Matched by COLOR ONLY — see attach_research_complete_label above. This path
  # has no create branch: a miss returns empty, and gate-research-complete.sh's
  # sole use of it treats empty as "not adding the label" and exits 0 (allow).
  # So a name predicate that stops matching does not deny and does not warn —
  # the green label lands, evaluate_research_complete never runs, and the card
  # is stranded in the Research column looking handed off. Keep this color-only.
  printf '%s' "$labels" | jq -r '.[] | select(.color=="green") | .id' 2>/dev/null | head -n1
}
