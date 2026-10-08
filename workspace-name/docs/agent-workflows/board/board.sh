#!/bin/bash
#
# board.sh: the board layer shared by every role's hooks.
#
# A hook sources this file. It loads board.conf, then the active adapter's
# tool map (tools.conf) and board functions (adapter.sh), then defines the
# helpers below, which work the same for every board.
#
# Loading, from a hook in <role>/.claude/hooks/:
#
#   _board_lib="$(dirname "$0")/../../../board/board.sh"
#   [[ -f "$_board_lib" ]] || exit 0
#   source "$_board_lib"
#   [[ "${BOARD_LOADED:-}" == "1" ]] || exit 0
#
# Rules for everything in this layer:
#   - Bash 3.2 compatible: no associative arrays, no mapfile, no ${var,,}.
#   - Safe under the caller's `set -euo pipefail`. Functions never exit and
#     never change shell options.
#   - Fail open. A function that cannot answer sets empty output and returns 0.

BOARD_LOADED=0
BOARD_SHARED_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [ -z "$BOARD_SHARED_DIR" ] || [ ! -f "$BOARD_SHARED_DIR/board.conf" ]; then
  return 0 2>/dev/null || exit 0
fi
# shellcheck disable=SC1091
. "$BOARD_SHARED_DIR/board.conf"

BOARD_ADAPTER_DIR="$BOARD_SHARED_DIR/adapters/${BOARD_ADAPTER:-trello}"
if [ ! -f "$BOARD_ADAPTER_DIR/tools.conf" ] || [ ! -f "$BOARD_ADAPTER_DIR/adapter.sh" ]; then
  return 0 2>/dev/null || exit 0
fi
# shellcheck disable=SC1091
. "$BOARD_ADAPTER_DIR/tools.conf"
# shellcheck disable=SC1091
. "$BOARD_ADAPTER_DIR/adapter.sh"
if [ -f "$BOARD_ADAPTER_DIR/watcher.sh" ]; then
  # shellcheck disable=SC1091
  . "$BOARD_ADAPTER_DIR/watcher.sh"
fi

# ============================================================================
# Columns
#
# The one rule for finding a column. A column matches when its name is the
# word, or contains the word as a separate word, case-insensitive. Characters
# other than letters and digits separate words, so "QA/QC" contains "qa". A
# word inside a longer word does not count: "Aqua" is not QA, "Snowflake" is
# not Now, "Development" is not Dev.
#
# No hook or watcher tests a column name any other way. The static check S12
# enforces that.
#
#   Column    Words
#   next      next
#   research  research
#   design    design
#   now       now, dev
#   qa        qa
#   done      done
# ============================================================================

# board_column_words <column>
board_column_words() {
  case "${1:-}" in
    next) printf 'next' ;;
    research) printf 'research' ;;
    design) printf 'design' ;;
    now) printf 'now dev' ;;
    qa) printf 'qa' ;;
    done) printf 'done' ;;
  esac
}

# board_column_regex <column>
#
# Prints the extended regex for the column, written for a lowercase name. Use
# it with `grep -iE` or jq `test($re; "i")`. Prints nothing for an unknown
# column.
board_column_regex() {
  local words alternatives
  words="$(board_column_words "${1:-}")"
  [ -n "$words" ] || return 0
  alternatives="$(printf '%s' "$words" | tr ' ' '|')"
  printf '(^|[^a-z0-9])(%s)([^a-z0-9]|$)' "$alternatives"
}

# board_column_is <column name> <column>
#
# Succeeds when the name belongs to the column.
board_column_is() {
  local re
  re="$(board_column_regex "${2:-}")"
  [ -n "$re" ] || return 1
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | grep -qE "$re"
}

# ============================================================================
# Tool calls
#
# hook_read_action reads the hook's stdin once and sets:
#
#   HOOK_INPUT               the raw payload
#   HOOK_TOOL                tool name
#   HOOK_ACTION              move | update | create | comment | comment_edit |
#                            comment_delete | shell | other
#   HOOK_CARD_ID             card id from the tool input
#   HOOK_DEST_STAGE_ID       destination column id (move) or target column (create)
#   HOOK_BOARD_ID            board id from the tool input, when given
#   HOOK_HAS_DESCRIPTION     true when the input has a description key, even ""
#   HOOK_DESCRIPTION         description text, empty when absent or null
#   HOOK_NAME                title from the tool input
#   HOOK_TEXT                comment text
#   HOOK_COMMENT_ID          comment id (comment edit and delete)
#   HOOK_COMMAND             shell command (Bash tool)
#   HOOK_LABEL_IDS           label ids from the input, one per line
#   HOOK_OTHER_INPUT_KEYS    input keys other than card, board and description
#   HOOK_CREATED_ID          created card, from either tool_response shape
#   HOOK_CREATED_NUMBER
#   HOOK_CREATED_TITLE
#   HOOK_CREATED_BOARD_ID
#   HOOK_CREATED_OBJECT_ID   created card id only when tool_response is a plain
#                            object (preserves one hook's current read)
#
# Field names in the tool input come from the adapter's tools.conf.
# ============================================================================
hook_read_action() {
  HOOK_INPUT="$(cat)"
  HOOK_TOOL=""
  HOOK_ACTION="other"
  HOOK_CARD_ID=""
  HOOK_DEST_STAGE_ID=""
  HOOK_BOARD_ID=""
  HOOK_HAS_DESCRIPTION="false"
  HOOK_DESCRIPTION=""
  HOOK_NAME=""
  HOOK_TEXT=""
  HOOK_COMMENT_ID=""
  HOOK_COMMAND=""
  HOOK_LABEL_IDS=""
  HOOK_OTHER_INPUT_KEYS="0"
  HOOK_CREATED_ID=""
  HOOK_CREATED_NUMBER=""
  HOOK_CREATED_TITLE=""
  HOOK_CREATED_BOARD_ID=""
  HOOK_CREATED_OBJECT_ID=""

  local assignments
  assignments="$(printf '%s' "$HOOK_INPUT" | jq -r \
    --arg card "$BOARD_IN_CARD" \
    --arg stage "$BOARD_IN_STAGE" \
    --arg board "$BOARD_IN_BOARD" \
    --arg desc "$BOARD_IN_DESC" \
    --arg name "$BOARD_IN_NAME" \
    --arg labels "$BOARD_IN_LABELS" \
    --arg text "$BOARD_IN_TEXT" \
    --arg comment "$BOARD_IN_COMMENT" \
    --arg rid "$BOARD_RESPONSE_ID" \
    --arg rnum "$BOARD_RESPONSE_NUMBER" \
    --arg rtitle "$BOARD_RESPONSE_TITLE" \
    --arg rboard "$BOARD_RESPONSE_BOARD" '
    def str: if . == null or . == false then "" elif type == "string" then . else tojson end;
    (.tool_input // {}) as $in
    | (if ($in | type) == "object" then $in else {} end) as $obj
    | (.tool_response) as $resp
    | (if ($resp | type) == "object" then $resp
       elif ($resp | type) == "array" and ($resp | length) > 0 and (($resp[0].text // null) != null)
         then ($resp[0].text | fromjson? // null)
       else null end) as $created
    | [
        @sh "HOOK_TOOL=\(.tool_name | str)",
        @sh "HOOK_CARD_ID=\($obj[$card] | str)",
        @sh "HOOK_DEST_STAGE_ID=\($obj[$stage] | str)",
        @sh "HOOK_BOARD_ID=\($obj[$board] | str)",
        @sh "HOOK_HAS_DESCRIPTION=\($obj | has($desc) | tostring)",
        @sh "HOOK_DESCRIPTION=\($obj[$desc] | str)",
        @sh "HOOK_NAME=\($obj[$name] | str)",
        @sh "HOOK_TEXT=\($obj[$text] | str)",
        @sh "HOOK_COMMENT_ID=\($obj[$comment] | str)",
        @sh "HOOK_COMMAND=\($obj.command | str)",
        @sh "HOOK_LABEL_IDS=\(($obj[$labels] // []) | if type == "array" then map(str) | join("\n") else str end)",
        @sh "HOOK_OTHER_INPUT_KEYS=\($obj | del(.[$card], .[$board], .[$desc]) | keys | length | tostring)",
        @sh "HOOK_CREATED_ID=\(($created // {}) | if type == "object" then .[$rid] else null end | str)",
        @sh "HOOK_CREATED_NUMBER=\(($created // {}) | if type == "object" then .[$rnum] else null end | str)",
        @sh "HOOK_CREATED_TITLE=\(($created // {}) | if type == "object" then .[$rtitle] else null end | str)",
        @sh "HOOK_CREATED_BOARD_ID=\(($created // {}) | if type == "object" then .[$rboard] else null end | str)",
        @sh "HOOK_CREATED_OBJECT_ID=\(if ($resp | type) == "object" then ($resp[$rid] | str) else "" end)"
      ]
    | join("\n")
  ' 2>/dev/null)" || return 0
  eval "$assignments"

  case "$HOOK_TOOL" in
    "$BOARD_TOOL_MOVE") HOOK_ACTION="move" ;;
    "$BOARD_TOOL_UPDATE") HOOK_ACTION="update" ;;
    "$BOARD_TOOL_CREATE") HOOK_ACTION="create" ;;
    "$BOARD_TOOL_COMMENT") HOOK_ACTION="comment" ;;
    "$BOARD_TOOL_COMMENT_EDIT") HOOK_ACTION="comment_edit" ;;
    "$BOARD_TOOL_COMMENT_DELETE") HOOK_ACTION="comment_delete" ;;
    Bash) HOOK_ACTION="shell" ;;
  esac
  return 0
}

# hook_emit_context <event> <text> [allow]
#
# Prints the additionalContext JSON Claude Code reads on exit 0. With a third
# argument of "allow", adds permissionDecision: "allow" (PreToolUse only).
hook_emit_context() {
  local event="$1" text="$2" allow="${3:-}"
  if [ "$allow" = "allow" ]; then
    jq -n --arg e "$event" --arg ctx "$text" '{hookSpecificOutput: {hookEventName: $e, permissionDecision: "allow", additionalContext: $ctx}}'
  else
    jq -n --arg e "$event" --arg ctx "$text" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $ctx}}'
  fi
}

BOARD_LOADED=1
