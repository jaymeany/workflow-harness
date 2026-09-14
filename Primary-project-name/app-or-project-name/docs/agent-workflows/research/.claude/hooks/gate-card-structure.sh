#!/bin/bash
#
# gate-card-structure.sh — Claude Code PreToolUse hook
#
# Enforces protocol/Research_Cards.md structural rules at card-write time. Fires
# on mcp__trello__update_card_details AND mcp__trello__move_card.
#
# Two checks, all deny-on-fail with explanatory stderr:
#
#   B. File-count cap — rejects cards with > MAX_FILES combined rows across
#      "## Files to Modify" and "## Files to Create" tables. Allows the
#      override if the description references a parent card ("Parent: #N")
#      or lists children ("Children: #N.1, #N.2").
#
#   C. Required-when-complete — when a description contains the literal
#      "## Research Complete" marker, every name in
#      REQUIRED_WHEN_RESEARCH_COMPLETE must appear as a ## section.
#
# Fires at WRITE time by design: move_card isn't always Claude's action
# (user may move via Trello UI), so structure must be validated when the
# description is being written, not when a move happens.
#
# Matcher in settings.json: "mcp__trello__(update_card_details|move_card)"
#
# Requires: jq, curl
# (curl is only used by the move_card branch, which fails open without it.
# Keep the Requires: line machine-parseable — bare comma-separated CLI
# names; audit-fail-open.sh parses it.)
#
# Exit codes:
#   0 — allow
#   2 — deny with stderr message
#
# Fails open (allow) if:
#   - config file missing
#   - jq missing
#   - no description present in input (label-only updates etc.)

set -euo pipefail

# ----------------------------------------------------------------------------
# Config load
# ----------------------------------------------------------------------------

CONFIG_FILE="$(dirname "$0")/protocol-enforcement.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Only the fields the checks below actually consume are required. ALLOWED_HEADERS
# is deliberately NOT in this list: no allowlist check exists in this script, and
# requiring an unused variable made pruning it from the conf silently disable the
# whole gate.
if [[ -z "${MAX_FILES:-}" || -z "${REQUIRED_WHEN_RESEARCH_COMPLETE[*]:-}" ]]; then
  echo "gate-card-structure.sh: config missing required fields, failing open" >&2
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# ----------------------------------------------------------------------------
# Read tool invocation
# ----------------------------------------------------------------------------

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

case "$tool_name" in
  mcp__trello__update_card_details|mcp__trello__move_card|mcp__trello__add_card_to_list) ;;
  *) exit 0 ;;
esac

# ----------------------------------------------------------------------------
# Resolve the description to validate
# ----------------------------------------------------------------------------

desc=""
if [[ "$tool_name" == "mcp__trello__update_card_details" || "$tool_name" == "mcp__trello__add_card_to_list" ]]; then
  # Description comes directly from the tool input (new card or explicit update).
  desc=$(echo "$input" | jq -r '.tool_input.description // empty')
  # No description in the payload (e.g., label-only update, or card being created
  # as a blank placeholder) → nothing to validate.
  [[ -z "$desc" ]] && exit 0
else
  # move_card: fetch the card's current description from Trello.
  card_id=$(echo "$input" | jq -r '.tool_input.cardId // empty')
  [[ -z "$card_id" ]] && exit 0
  TRELLO_TOKEN_VALUE="${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
  if [[ -z "${TRELLO_API_KEY:-}" || -z "$TRELLO_TOKEN_VALUE" ]] || ! command -v curl >/dev/null 2>&1; then
    exit 0
  fi
  card=$(curl -s --max-time 5 "https://api.trello.com/1/cards/${card_id}?fields=desc&key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN_VALUE}" 2>/dev/null || echo '{}')
  desc=$(echo "$card" | jq -r '.desc // empty')
  [[ -z "$desc" ]] && exit 0
fi

# ============================================================================
# Check B — File-count cap
# ============================================================================

# Count data rows in a markdown table inside a named ## section.
# Header row = first "|..."; separator = "| --- |..."; data rows follow.
count_table_rows_under_section() {
  local section_name="$1"
  printf '%s\n' "$desc" \
    | awk -v section="## ${section_name}" '
        $0 == section { flag = 1; next }
        /^## / { flag = 0 }
        flag
      ' \
    | awk '
        # Skip separator rows that are mostly dashes/pipes/spaces
        /^\|[[:space:]]*[-][-:| ]*\|[[:space:]]*$/ { next }
        /^\|/ {
          if (header_seen) data++
          else header_seen = 1
        }
        END { print (data ? data : 0) }
      '
}

modify_count=$(count_table_rows_under_section "Files to Modify")
create_count=$(count_table_rows_under_section "Files to Create")
total_files=$(( modify_count + create_count ))

if (( total_files > MAX_FILES )); then
  if ! printf '%s\n' "$desc" | grep -qE '^[[:space:]]*(Parent|Children):'; then
    {
      echo "BLOCKED: card lists $total_files files (cap: $MAX_FILES)."
      echo ""
      echo "  Files to Modify rows: $modify_count"
      echo "  Files to Create rows: $create_count"
      echo ""
      echo "Research_Role.md § Card Sizing mandates split at >$MAX_FILES files."
      echo ""
      echo "To proceed, either:"
      echo "  (a) Split this card into child cards, each with ≤ $MAX_FILES files."
      echo "      Add a line 'Children: #<n>.1, #<n>.2, ...' to this card."
      echo "  (b) If this card is itself a child, add a line 'Parent: #<n>'"
      echo "      so the hook recognizes the split structure is in place."
    } >&2
    exit 2
  fi
fi

# ============================================================================
# Check C — Required sections when "## Research Complete" is declared
# ============================================================================

if printf '%s\n' "$desc" | grep -qE '^## Research Complete[[:space:]]*$'; then
  missing=()
  for slot in "${REQUIRED_WHEN_RESEARCH_COMPLETE[@]}"; do
    # Each slot is "|"-separated alternatives. Satisfied if any matches.
    # Starts-with match — allows variants like "Services Discovered (with evidence)".
    slot_satisfied=0
    IFS='|' read -ra alternatives <<< "$slot"
    for alt in "${alternatives[@]}"; do
      if printf '%s\n' "$desc" | grep -qE "^## ${alt}([[:space:]]|\$|\()"; then
        slot_satisfied=1
        break
      fi
    done
    if [[ "$slot_satisfied" == "0" ]]; then
      missing+=("$slot")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    {
      echo "BLOCKED: card declares \"## Research Complete\" but is missing required sections."
      echo ""
      echo "Missing:"
      printf '  - ## %s\n' "${missing[@]}"
      echo ""
      echo "When a card declares Research Complete, these sections must be present:"
      printf '  - ## %s\n' "${REQUIRED_WHEN_RESEARCH_COMPLETE[@]}"
      echo ""
      echo "Either add the missing sections with real content, or remove the"
      echo "\"## Research Complete\" marker until research is actually complete."
      echo ""
      echo "See Research_Role.md § Handoff to Dev."
    } >&2
    exit 2
  fi
fi

exit 0
