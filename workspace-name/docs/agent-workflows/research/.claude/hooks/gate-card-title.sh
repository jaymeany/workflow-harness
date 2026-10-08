#!/bin/bash
#
# gate-card-title.sh — Claude Code PreToolUse hook
#
# Enforces the Research-role card naming convention. Card titles take the
# form:
#
#   #<idShort> <title> <24-char Trello card id>
#
# Example: "#58 Add login flow rRbWenynABCDEF1234567890"
#
# THREE PARTS. A trailing worktree tag naming the repo a card belongs to is a
# convention from multi-repo boards. On a single board it distinguishes nothing.
#
# THE TAG IS TOLERATED, NOT REQUIRED. The trailing group stays optional.
# BOARD_TAG_MAP is still read, because the optional group is matched against
# the real tag for the card's board rather than against any trailing word.
#
# Why a hook: the convention has been documented in Research_Role.md since
# day one. It was repeatedly violated in practice — the agent would create
# cards with descriptive-only titles and forget the rename pass. Cards on
# the board ended up in two shapes (canonical vs. ad-hoc), making board
# scans noisy and breaking any tool that parses the idShort/id out of the
# title. This hook makes "untitled" a write-time error.
#
# Tag source: BOARD_TAG_MAP in protocol-enforcement.conf maps each board id to
# its worktree tag. A card on an UNMAPPED board is not checked at all — the hook
# does not impose a shape where the real mapping is unknown (fail open).
#
# Two checks:
#
#   On mcp__trello__add_card_to_list:
#     The card has no idShort or 24-char id until Trello's response. The
#     canonical name cannot be assembled at create time. Require an explicit
#     placeholder marker so the create signals "I will rename this":
#
#       ^\[TBD\] .+$
#
#     The canonical title is then patched in via update_card_details after
#     the create returns, using the idShort + id from the response.
#
#   On mcp__trello__update_card_details when tool_input.name is set:
#     Fetch the card's idShort + id + idBoard from Trello, derive the board's
#     tag from BOARD_TAG_MAP, and require:
#
#       ^#<idShort> .+ <id>( <tag>)?$
#
#     Block on mismatch with the actual required string in the error so the
#     agent doesn't have to guess.
#
# Matcher in settings.json:
#   "mcp__trello__(add_card_to_list|update_card_details)"
#
# Config (sourced from protocol-enforcement.conf):
#   BOARD_TAG_MAP — associative array: board id → worktree tag.
#
# Environment:
#   TRELLO_API_KEY — required for the Trello board/card lookups
#   TRELLO_API_TOKEN or TRELLO_TOKEN — required for the Trello lookups
#
# Requires: jq, curl (for the lookups)
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - jq missing
#   - config file missing or BOARD_TAG_MAP undefined
#   - missing env / curl / api unreachable (so transient Trello issues don't
#     block legitimate work)
#   - the card's board is not in BOARD_TAG_MAP (no invented tag)

# Requires-Path: ../board/board.sh
# Board-Actions: create, update

set -euo pipefail

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------

CONFIG_FILE="$(dirname "$0")/protocol-enforcement.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Need the board→tag lookup (board_tag, defined in the conf) to enforce
# anything. Without it, fail open.
if ! command -v board_tag >/dev/null 2>&1; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# ----------------------------------------------------------------------------
# Read tool invocation
# ----------------------------------------------------------------------------

# The board layer: tool names, board calls and the tool-call reader.
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../board/board.sh" 2>/dev/null || exit 0
[[ "${BOARD_LOADED:-}" == "1" ]] || exit 0

hook_read_action
new_name="$HOOK_NAME"

case "$HOOK_ACTION" in
  create|update) ;;
  *) exit 0 ;;
esac

# board_tag <boardId> → worktree tag (or empty) — defined in
# protocol-enforcement.conf, sourced above. Kept there (a 3.2-safe case
# function, not an associative array) so the config lives in one place.

# ============================================================================
# add_card_to_list — require [TBD] placeholder
# ============================================================================

if [[ "$HOOK_ACTION" == "create" ]]; then
  if [[ -z "$new_name" ]]; then
    exit 0
  fi
  if [[ "$new_name" =~ ^\[TBD\][[:space:]].+$ ]]; then
    exit 0
  fi

  # The destination board used to be resolved here, solely so the example below
  # could print that board's tag. The example carries no tag now, so the lookup
  # is gone and the create path makes no network call.

  cat >&2 <<EOF
BLOCKED: card create with non-placeholder name.

Card titles follow three parts, and there is no fourth field:
  #<idShort> <title> <24-char Trello id>

Trello assigns idShort and the 24-char id at create time, so the canonical
title cannot be set on the create call itself. Use a placeholder, then
rename via update_card_details using the IDs from the create response:

  Step 1 — create with placeholder:
      mcp__trello__add_card_to_list({
        listId: "...",
        name: "[TBD] $new_name",
        description: "..."
      })

  Step 2 — rename using the IDs from the response:
      mcp__trello__update_card_details({
        cardId: "<id from response>",
        name: "#<idShort> $new_name <id>"
      })

The rename must happen in the same turn as the create. Do not ship the
card with the [TBD] name still on it — gate-card-title.sh will block any
later update_card_details that tries to reuse a non-canonical name.

See Research_Role.md § Card Management § Naming convention.
EOF
  exit 2
fi

# ============================================================================
# update_card_details — require canonical name when name is being changed
# ============================================================================

# Only fire when name is actually being set (description-only updates pass).
if [[ -z "$new_name" ]]; then
  exit 0
fi

card_id="$HOOK_CARD_ID"
if [[ -z "$card_id" ]]; then
  exit 0
fi

if ! board_credentials_present || ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

# Fetch the card number, id and board id. The board id is what lets us
# derive the correct tag for THIS card, rather than a hardcoded default.
board_card_get card "$card_id"
id_short=""
trello_id=""
id_board=""
if [[ -n "$card" ]]; then
  id_short=$(printf '%s' "$card" | jq -r '.number // empty')
  trello_id=$(printf '%s' "$card" | jq -r '.id // empty')
  id_board=$(printf '%s' "$card" | jq -r '.board_id // empty')
fi

# If the lookup didn't return what we need, fail open. This hook should not
# block on Trello flakiness — the structural gate already protects content.
if [[ -z "$id_short" || -z "$trello_id" ]]; then
  exit 0
fi

# Derive the tag from the board the card actually lives on. An unmapped board
# is NOT tag-checked — we never impose an invented tag where reality is unknown.
tag="$(board_tag "$id_board")"
if [[ -z "$tag" ]]; then
  exit 0
fi

# Required pattern: #<idShort> <title> <24-char id>, with the board tag OPTIONAL.
#
# THE TAG IS NOT REQUIRED. It is a repo suffix from multi-repo boards. On a
# single board every card resolves to the same value, so it is optional: names
# with it stay valid and three-part names pass.
# Title must be at least one character; trailing whitespace not tolerated.
required_regex="^#${id_short}[[:space:]].+[[:space:]]${trello_id}([[:space:]]${tag})?$"

if [[ "$new_name" =~ $required_regex ]]; then
  exit 0
fi

# Build a sample showing the agent the exact target string. Extract the
# title chunk from the proposed name so the message can show what to keep.
suggested_title="$new_name"
# If the agent supplied a partial canonical attempt, strip a leading "#N "
# and any trailing " <hex> <tag>" so the suggestion shows just the title.
suggested_title=$(printf '%s' "$suggested_title" | sed -E "s/^#[0-9]+ //")
suggested_title=$(printf '%s' "$suggested_title" | sed -E "s/ [a-f0-9]{24}( ${tag})?\$//")
suggested_title=$(printf '%s' "$suggested_title" | sed -E "s/^\[TBD\] //")

cat >&2 <<EOF
BLOCKED: card title does not match required convention.

Required, three parts:
  #${id_short} <title> ${trello_id}

Got:
  ${new_name}

Proposed canonical title (rebuild from your title text):
  #${id_short} ${suggested_title} ${trello_id}

Re-issue the update with that exact name.

Note on whitespace: single spaces between every segment; no leading or
trailing whitespace; title may contain spaces but must be non-empty.

See Research_Role.md § Card Management § Naming convention.
EOF
exit 2
