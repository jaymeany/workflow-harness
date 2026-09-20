#!/bin/bash
#
# audit-fail-open.sh — Claude Code SessionStart hook
#
# Surfaces silently-disabled hooks at session start. Discovers every
# sibling hook script in this directory, parses its header for
# declared preconditions, and validates them against the current
# shell. If any hook would currently fail open (declared CLI dep not
# on PATH, declared env var unset), emits a loud banner via
# additionalContext + stderr listing every affected hook and which
# preconditions are missing.
#
# Stays silent when every hook's preconditions are met.
#
# Header conventions parsed (every hook in this template already
# follows them — that's what makes this audit agnostic):
#
#   # Requires: <comma-separated CLI names>
#   # Requires-Path: <comma-separated paths, relative to CLAUDE_PROJECT_DIR>
#
#   # Environment:
#   #   VAR_NAME — required
#   #   VAR_A or VAR_B — required (either name accepted)
#
# No hardcoded hook names, no hardcoded dep list. Drops into any role
# template's .claude/hooks/ and works as long as the header convention
# is followed.
#
# Hook event: SessionStart
# Exit codes: always 0 — informational only, never blocks a session.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

problems=()

# Shared hooks live outside this directory (../../../shared/), the way
# board/board.sh does. They are still this role's hooks: settings.json points
# at them and they run with this role's CLAUDE_PROJECT_DIR. Auditing only the
# local directory would silently drop them from the fail-open check the moment
# a hook was moved there.
for hook_path in "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/../../../shared/*.sh; do
  [[ -f "$hook_path" ]] || continue
  hook_name="$(basename "$hook_path")"
  [[ "$hook_name" == "$SELF_NAME" ]] && continue

  # ---- Pass 1: capture "# Requires: ..." line ----
  requires_line=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^#[[:space:]]*Requires:[[:space:]]*(.*)$ ]]; then
      requires_line="${BASH_REMATCH[1]}"
      break
    fi
  done < "$hook_path"

  required_clis=()
  if [[ -n "$requires_line" ]]; then
    IFS=',' read -ra raw_clis <<< "$requires_line"
    for cli in "${raw_clis[@]}"; do
      # Take the first whitespace-delimited word from the token, then
      # validate shape. This handles prose tails like
      # `curl (for X branch)` — `curl` is extracted and accepted; the
      # parenthetical is ignored. Token must look like a CLI name:
      # lowercase start, lowercase/digit/underscore/hyphen body. Filters
      # out env-var-shaped tokens (ALL_CAPS) that occasionally land in
      # malformed `# Requires:` lines.
      first_word="$(echo "$cli" | awk '{print $1}')"
      [[ "$first_word" =~ ^[a-z][a-z0-9_-]*$ ]] && required_clis+=("$first_word")
    done
  fi

  # ---- Pass 1b: capture "# Requires-Path: ..." line ----
  # A hook that fails open when a DIRECTORY or FILE is absent is invisible
  # to a check of PATH and the environment alone. For example, the PreCompact
  # handoff hook is inert when docs/handoffs/ does not exist.
  # A path dependency is a precondition like any other. Declare it and it
  # is audited; leave it undeclared and the gate is silently off.
  requires_path_line=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^#[[:space:]]*Requires-Path:[[:space:]]*(.*)$ ]]; then
      requires_path_line="${BASH_REMATCH[1]}"
      break
    fi
  done < "$hook_path"

  required_paths=()
  if [[ -n "$requires_path_line" ]]; then
    IFS=',' read -ra raw_paths <<< "$requires_path_line"
    for pth in "${raw_paths[@]}"; do
      # First whitespace-delimited token, same shape rule as Requires:
      # prose tails after the path are ignored.
      first_word="$(echo "$pth" | awk '{print $1}')"
      [[ -n "$first_word" ]] && required_paths+=("$first_word")
    done
  fi

  # ---- Pass 2: capture "# Environment:" block ----
  required_env_groups=()
  inside=0
  while IFS= read -r raw; do
    if [[ $inside -eq 0 ]]; then
      [[ "$raw" =~ ^#[[:space:]]*Environment:[[:space:]]*$ ]] && inside=1
      continue
    fi
    # End-of-block: non-comment line, blank comment, or another section header.
    if [[ ! "$raw" =~ ^# ]] || [[ "$raw" =~ ^#[[:space:]]*$ ]]; then
      inside=0
      continue
    fi
    if [[ "$raw" =~ ^#[[:space:]]+[A-Z][a-zA-Z[:space:]]*: ]]; then
      inside=0
      continue
    fi
    # Match: "VAR_NAME [or VAR_NAME2] <separator> required ..."
    if [[ "$raw" =~ ([A-Z_][A-Z0-9_]*)([[:space:]]+or[[:space:]]+([A-Z_][A-Z0-9_]*))?.*required ]]; then
      names="${BASH_REMATCH[1]}"
      if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
        names="$names ${BASH_REMATCH[3]}"
      fi
      required_env_groups+=("$names")
    fi
  done < "$hook_path"

  # ---- Validate ----
  missing=()
  if [[ ${#required_clis[@]} -gt 0 ]]; then
    for cli in "${required_clis[@]}"; do
      command -v "$cli" >/dev/null 2>&1 || missing+=("CLI: $cli")
    done
  fi
  if [[ ${#required_paths[@]} -gt 0 ]]; then
    for pth in "${required_paths[@]}"; do
      # Resolve relative to the role directory, which is what a hook sees.
      case "$pth" in
        /*) abs="$pth" ;;
        *)  abs="${CLAUDE_PROJECT_DIR:-.}/$pth" ;;
      esac
      [[ -e "$abs" ]] || missing+=("PATH: $pth")
    done
  fi
  if [[ ${#required_env_groups[@]} -gt 0 ]]; then
    for group in "${required_env_groups[@]}"; do
      satisfied=0
      for name in $group; do
        val="${!name:-}"
        if [[ -n "$val" ]]; then
          satisfied=1
          break
        fi
      done
      if [[ $satisfied -eq 0 ]]; then
        pretty="$(echo "$group" | sed 's/ / or /g')"
        missing+=("ENV: $pretty")
      fi
    done
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    joined=""
    for m in "${missing[@]}"; do
      [[ -n "$joined" ]] && joined="$joined, "
      joined="$joined$m"
    done
    problems+=("$hook_name → $joined")
  fi
done

[[ ${#problems[@]} -eq 0 ]] && exit 0

# ---- Emit loud banner ----
banner=""
banner+=$'\n'
banner+="================================================================"$'\n'
banner+="  HOOK FAIL-OPEN ALERT"$'\n'
banner+="================================================================"$'\n'
banner+=$'\n'
banner+="The hooks below have unmet declared preconditions and will"$'\n'
banner+="silently allow tool calls they were installed to gate. Self-"$'\n'
banner+="enforce the corresponding rules until the missing deps are"$'\n'
banner+="restored:"$'\n'
banner+=$'\n'
for p in "${problems[@]}"; do
  banner+="  • $p"$'\n'
done
banner+=$'\n'
banner+="================================================================"$'\n'

# Stderr — visible in terminal session-start output.
printf '%s' "$banner" >&2

# additionalContext — surfaced into the agent's session-start context.
# If jq is itself missing, the banner already printed to stderr is the
# only signal — and a missing jq will be among the listed problems.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$banner" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    }
  }'
fi

exit 0
