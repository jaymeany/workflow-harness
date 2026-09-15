#!/bin/bash
#
# adapter.sh: the Trello adapter's board functions.
#
# Sourced by board.sh. Implements the board contract in board/CONTRACT.md
# with curl and jq against the Trello REST API.
#
# Every read takes the name of a variable to fill, instead of printing, so the
# caller can also see why a call failed. After each call, BOARD_STATUS is one
# of:
#
#   ok          the call worked; for reads, the body was a JSON object or array
#   nocreds     the credentials are missing; no call was made
#   transport   curl failed; there was no response
#   body        a response arrived, but it was not the JSON the call expects,
#               for example an HTTP error message
#
# On any status other than ok, a read sets its variable to "". Functions never
# exit and always return 0, so they are safe under `set -euo pipefail`.
#
# Requires: jq, curl
# Environment:
#   TRELLO_API_KEY: required
#   TRELLO_API_TOKEN or TRELLO_TOKEN: required

BOARD_STATUS="ok"

board_credentials_present() {
  [ -n "${TRELLO_API_KEY:-}" ] && [ -n "${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}" ]
}

board_available() {
  command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && board_credentials_present
}

# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------

# _trello_url <path> [query]
_trello_url() {
  local __tr_query="${2:-}"
  printf 'https://api.trello.com/1%s?%skey=%s&token=%s' \
    "$1" "${__tr_query:+${__tr_query}&}" "${TRELLO_API_KEY:-}" "${TRELLO_API_TOKEN:-${TRELLO_TOKEN:-}}"
}

# _trello_read <out var> <path> [query]
_trello_read() {
  local __tr_out="$1" __tr_body="" __tr_rc=0
  printf -v "$__tr_out" '%s' ""
  if ! board_credentials_present; then
    BOARD_STATUS="nocreds"
    return 0
  fi
  __tr_body="$(curl -s --max-time 5 "$(_trello_url "$2" "${3:-}")" 2>/dev/null)" || __tr_rc=$?
  if [ "$__tr_rc" -ne 0 ]; then
    BOARD_STATUS="transport"
    return 0
  fi
  if ! printf '%s' "$__tr_body" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
    BOARD_STATUS="body"
    return 0
  fi
  printf -v "$__tr_out" '%s' "$__tr_body"
  BOARD_STATUS="ok"
  return 0
}

# _trello_send <out var> <METHOD> <path> [query] [form field]
#
# Sends a write. Fills <out var> with the response body when it is JSON.
_trello_send() {
  local __tr_out="$1" __tr_method="$2" __tr_path="$3" __tr_query="${4:-}" __tr_form="${5:-}"
  local __tr_body="" __tr_rc=0
  printf -v "$__tr_out" '%s' ""
  if ! board_credentials_present; then
    BOARD_STATUS="nocreds"
    return 0
  fi
  if [ -n "$__tr_form" ]; then
    __tr_body="$(curl -s --max-time 5 -X "$__tr_method" --data-urlencode "$__tr_form" \
      "$(_trello_url "$__tr_path" "$__tr_query")" 2>/dev/null)" || __tr_rc=$?
  else
    __tr_body="$(curl -s --max-time 5 -X "$__tr_method" \
      "$(_trello_url "$__tr_path" "$__tr_query")" 2>/dev/null)" || __tr_rc=$?
  fi
  if [ "$__tr_rc" -ne 0 ]; then
    BOARD_STATUS="transport"
    return 0
  fi
  BOARD_STATUS="ok"
  if printf '%s' "$__tr_body" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
    printf -v "$__tr_out" '%s' "$__tr_body"
  fi
  return 0
}

# _board_map <out var> <json> <jq filter>
_board_map() {
  local __bm_out="$1" __bm_json="$2" __bm_mapped="" __bm_rc=0
  printf -v "$__bm_out" '%s' ""
  [ -n "$__bm_json" ] || return 0
  __bm_mapped="$(printf '%s' "$__bm_json" | jq -c "$3" 2>/dev/null)" || __bm_rc=$?
  if [ "$__bm_rc" -ne 0 ]; then
    BOARD_STATUS="body"
    return 0
  fi
  printf -v "$__bm_out" '%s' "$__bm_mapped"
}

# _board_text <out var> <json> <jq filter producing a string>
_board_text() {
  local __bt_out="$1" __bt_json="$2" __bt_text="" __bt_rc=0
  printf -v "$__bt_out" '%s' ""
  [ -n "$__bt_json" ] || return 0
  __bt_text="$(printf '%s' "$__bt_json" | jq -r "$3" 2>/dev/null)" || __bt_rc=$?
  if [ "$__bt_rc" -ne 0 ]; then
    BOARD_STATUS="body"
    return 0
  fi
  printf -v "$__bt_out" '%s' "$__bt_text"
}

_uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

# board_card_get <out var> <card id>
#   {"id","number","title","description","stage_id","board_id"}
board_card_get() {
  local __raw=""
  _trello_read __raw "/cards/$2" "fields=id,idShort,name,desc,idList,idBoard"
  _board_map "$1" "$__raw" '{id: .id, number: .idShort, title: .name, description: .desc, stage_id: .idList, board_id: .idBoard}'
}

# board_card_stage_name <out var> <card id>
#   plain text: the name of the column the card is in
board_card_stage_name() {
  local __raw=""
  _trello_read __raw "/cards/$2" "fields=idList&list=true&list_fields=name"
  _board_text "$1" "$__raw" '.list.name // empty'
}

# board_stage_get <out var> <column id>
#   {"id","name","board_id"}
board_stage_get() {
  local __raw=""
  _trello_read __raw "/lists/$2" "fields=name,idBoard"
  _board_map "$1" "$__raw" '{id: .id, name: .name, board_id: .idBoard}'
}

# board_stages <out var> <board id>
#   [{"id","name"}] in board order
board_stages() {
  local __raw=""
  _trello_read __raw "/boards/$2/lists" "fields=id,name"
  _board_map "$1" "$__raw" 'map({id: .id, name: .name})'
}

# board_stage_cards <out var> <column id>
#   [{"id","number","title"}] in board position order
board_stage_cards() {
  local __raw=""
  _trello_read __raw "/lists/$2/cards" "fields=id,idShort,name"
  _board_map "$1" "$__raw" 'map({id: .id, number: .idShort, title: .name})'
}

# board_labels <out var> <board id>
#   [{"id","name","color"}]
board_labels() {
  local __raw=""
  _trello_read __raw "/boards/$2/labels" "fields=id,name,color"
  _board_map "$1" "$__raw" 'map({id: .id, name: .name, color: .color})'
}

# board_card_notes <out var> <card id> <limit>
#   newest first: [{"id","text","created_at","edited_at"}]
board_card_notes() {
  local __raw=""
  _trello_read __raw "/cards/$2/actions" "filter=commentCard&limit=$3"
  _board_map "$1" "$__raw" 'map({id: .id, text: .data.text, created_at: .date, edited_at: (.data.dateLastEdited // null)})'
}

# board_card_activity <out var> <card id> <limit>
#   newest first, notes and card updates in one window:
#   [{"kind":"note","id","text","created_at","edited_at"}
#    |{"kind":"description_change","id","old_description","created_at"}
#    |{"kind":"update_other","id","created_at"}]
board_card_activity() {
  local __raw=""
  _trello_read __raw "/cards/$2/actions" "filter=commentCard,updateCard&limit=$3"
  _board_map "$1" "$__raw" 'map(
    if .type == "commentCard" then
      {kind: "note", id: .id, text: .data.text, created_at: .date, edited_at: (.data.dateLastEdited // null)}
    elif ((.data.old // {}) | has("desc")) then
      {kind: "description_change", id: .id, old_description: .data.old.desc, created_at: .date}
    else
      {kind: "update_other", id: .id, created_at: .date}
    end)'
}

# ---------------------------------------------------------------------------
# State labels
# ---------------------------------------------------------------------------

_board_state_color() {
  eval "printf '%s' \"\${BOARD_LABEL_COLOR_$1:-}\""
}

_board_state_name() {
  eval "printf '%s' \"\${BOARD_LABEL_NAME_$1:-}\""
}

# board_state_label_pick <out var> <labels json> <state>
#   the id of the first label for the state, or "". No network.
board_state_label_pick() {
  local __color
  __color="$(_board_state_color "$3")"
  printf -v "$1" '%s' ""
  [ -n "$__color" ] && [ -n "$2" ] || return 0
  _board_text "$1" "$2" "[.[] | select(.color == \"$__color\")][0].id // empty"
}

# board_label_create <out var> <board id> <state>
#   creates the state's label on the board; fills the new label id
board_label_create() {
  local __raw="" __color __name
  __color="$(_board_state_color "$3")"
  __name="$(_board_state_name "$3")"
  printf -v "$1" '%s' ""
  [ -n "$__color" ] || return 0
  _trello_send __raw POST "/labels" "name=$(_uri "$__name")&color=${__color}&idBoard=$2"
  _board_text "$1" "$__raw" '.id // empty'
}

# ---------------------------------------------------------------------------
# Writes. Each sets BOARD_STATUS to ok, nocreds or transport.
# ---------------------------------------------------------------------------

# board_card_label_add <card id> <label id>
board_card_label_add() {
  local __ignored=""
  _trello_send __ignored POST "/cards/$1/idLabels" "value=$2"
}

# board_card_label_remove <card id> <label id>
board_card_label_remove() {
  local __ignored=""
  _trello_send __ignored DELETE "/cards/$1/idLabels/$2"
}

# board_card_move <card id> <column id>
board_card_move() {
  local __ignored=""
  _trello_send __ignored PUT "/cards/$1/idList" "value=$2"
}

# board_card_rename <card id> <title>
board_card_rename() {
  local __ignored=""
  _trello_send __ignored PUT "/cards/$1" "" "name=$2"
}
