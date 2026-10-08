#!/bin/bash
#
# watcher.sh: the Trello adapter's column watcher.
#
# board_watch_command <watch tag> <board id> <column regex>
#
# Prints the shell loop a role's SessionStart hook hands to Claude Code's
# Monitor tool. The loop polls the column every 20 seconds, read-only, and
# prints one line per card that arrives. The column regex comes from
# board_column_regex, so the watcher finds its column by the same rule as
# every hook.
#
# Inputs must not contain the & character.

board_watch_command() {
  local tag="$1" board="$2" re="$3" template=""
  IFS= read -r -d '' template <<'WATCH_LOOP' || true
WATCH_TAG="@WATCH_TAG@"
BOARD="@BOARD@"
WORD_RE='@WORD_RE@'
TOK="${TRELLO_API_TOKEN:-$TRELLO_TOKEN}"
LIST=""
warned=0
seen=""
first=1
while true; do
  if [ -z "$LIST" ]; then
    LIST=$(curl -sf --max-time 10 -G "https://api.trello.com/1/boards/$BOARD/lists" --data-urlencode "fields=name" --data-urlencode "key=$TRELLO_API_KEY" --data-urlencode "token=$TOK" 2>/dev/null | jq -r --arg re "$WORD_RE" '[.[] | select(.name | test($re; "i"))][0].id // empty' 2>/dev/null) || LIST=""
    if [ -z "$LIST" ]; then
      if [ "$warned" -eq 0 ]; then
        echo "TRELLO watcher: no column found on board $BOARD yet, or Trello did not answer. Retrying every 20s."
        warned=1
      fi
      sleep 20
      continue
    fi
  fi
  out=$(curl -sf --max-time 10 -G "https://api.trello.com/1/lists/$LIST/cards" --data-urlencode "fields=idShort,name" --data-urlencode "key=$TRELLO_API_KEY" --data-urlencode "token=$TOK" 2>/dev/null) || out=""
  if [ -n "$out" ]; then
    if lines=$(printf '%s' "$out" | jq -r '.[] | (.idShort|tostring) as $n | (if (.name|startswith("#"+$n+" ")) then .name else "#"+$n+" "+.name end) as $t | .id + " " + $t' 2>/dev/null); then
      cur=""
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        id="${line%% *}"
        cur="$cur|$id|"
        case "$seen" in *"|$id|"*) continue ;; esac
        if [ "$first" -eq 1 ]; then
          echo "TRELLO in-column at boot: ${line#* }"
        else
          echo "TRELLO card arrival: ${line#* } (detected $(date -u +%H:%M:%SZ))"
        fi
      done <<< "$lines"
      seen="$cur"
      first=0
    fi
  fi
  sleep 20
done
WATCH_LOOP
  template="${template%$'\n'}"
  template=${template//@WATCH_TAG@/$tag}
  template=${template//@BOARD@/$board}
  template=${template//@WORD_RE@/$re}
  printf '%s' "$template"
}
