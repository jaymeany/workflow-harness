# Board contract

The hooks never talk to a board directly. They call the functions in this contract. An adapter implements the functions for one board product. Trello is the adapter that ships, in `adapters/trello/`.

To use another board, write an adapter that meets this contract, set `BOARD_ADAPTER` in `board.conf`, and update the matchers in each role's `settings.json`. The offline suite and the static checks tell you when something is missing.

## Layout

```
board/
  board.sh          loads the adapter; the column rule, the tool-call reader, output helpers
  board.conf        BOARD_ADAPTER and BOARD_ID
  CONTRACT.md       this file
  adapters/<name>/
    tools.conf      tool names, input field names, API host, state labels
    adapter.sh      the board functions below
    watcher.sh      board_watch_command, the column watcher loop
    ADAPTER.md      setup and every product-specific fact
```

Every role's hooks share this one copy. A role folder can't be lifted out of the workspace on its own, and it couldn't before: hooks already find handoffs and repos by their position.

## Rules

- **Bash 3.2.** No associative arrays, no `mapfile`, no `${var,,}`.
- **Safe to call.** Functions never exit and never change the caller's shell options. They are safe under `set -euo pipefail`.
- **Fail open.** A function that can't answer returns 0 and leaves its output empty.
- **Say why.** After each call, `BOARD_STATUS` is `ok`, `nocreds`, `transport` or `body`. Hooks use it where the reason changes what they do.
- **Reads fill a variable.** The first argument is the variable's name. This keeps `BOARD_STATUS` visible to the caller.
- **No disk state.** Hooks run in parallel, so functions keep nothing between calls.

## Names

| Contract | Trello |
|---|---|
| column | list |
| card `number` | `idShort` |
| card `title` | `name` |
| card `description` | `desc` |
| note | comment |
| state label | a label found by its color |

Ids are opaque strings.

## Functions

### Availability

| Function | Succeeds when |
|---|---|
| `board_credentials_present` | The adapter's credentials are set |
| `board_available` | The tools and credentials the adapter needs are present |

### Reads

| Function | Fills |
|---|---|
| `board_card_get <var> <card>` | `{"id","number","title","description","stage_id","board_id"}` |
| `board_card_stage_name <var> <card>` | The name of the card's column, as text |
| `board_stage_get <var> <column>` | `{"id","name","board_id"}` |
| `board_stages <var> <board>` | `[{"id","name"}]` in board order |
| `board_stage_cards <var> <column>` | `[{"id","number","title"}]` in board order |
| `board_labels <var> <board>` | `[{"id","name","color"}]` |
| `board_card_notes <var> <card> <limit>` | Newest first: `[{"id","text","created_at","edited_at"}]` |
| `board_card_activity <var> <card> <limit>` | Newest first, notes and updates in one window. Each item has `kind`: `note`, `description_change` (with `old_description`) or `update_other` |

### State labels

The states are `research_complete`, `needs_research`, `qa_fail`, `qa_complete` and `tracking`. The hooks never see colors or product label names.

| Function | Does |
|---|---|
| `board_state_label_pick <var> <labels json> <state>` | Fills the id of the state's label from a `board_labels` result. No network |
| `board_label_create <var> <board> <state>` | Creates the state's label and fills its id |

Each hook decides whether a missing label is created. That choice is part of the workflow, not the adapter.

### Writes

Each sets `BOARD_STATUS` to `ok`, `nocreds` or `transport`.

| Function | Does |
|---|---|
| `board_card_label_add <card> <label>` | Attaches a label |
| `board_card_label_remove <card> <label>` | Removes a label |
| `board_card_move <card> <column>` | Moves a card |
| `board_card_rename <card> <title>` | Renames a card |

## Columns

`board.sh` holds the one rule for finding a column. It is the same for every adapter.

A column matches when its name is the word, or contains the word as a separate word, case-insensitive. Characters other than letters and digits separate words.

| Column | Words | Matches | Does not match |
|---|---|---|---|
| `next` | next | Next, Up Next | |
| `research` | research | Research, Apple research | Researcher notes |
| `design` | design | Design, Design column | Designer |
| `now` | now, dev | Now, Dev | Snowflake, Development |
| `qa` | qa | QA, QA/QC, QA Pony, Pony QA | Aqua |
| `done` | done | Done | Undone |

| Function | Does |
|---|---|
| `board_column_is <name> <column>` | Succeeds when the name belongs to the column |
| `board_column_regex <column>` | Prints the rule as a regex for `grep -iE` or jq `test($re; "i")` |

No hook or watcher tests a column name any other way. Static check S12 fails the suite if one does.

## Tool calls

`hook_read_action` reads a hook's stdin once and sets `HOOK_ACTION` and the fields a hook needs: card id, destination column, description, title, comment text, label ids, and the created card from either response shape. The field names come from `tools.conf`. See the header of `board.sh` for the full list.

`HOOK_ACTION` is one of `move`, `update`, `create`, `comment`, `comment_edit`, `comment_delete`, `shell` or `other`.

## tools.conf

An adapter's `tools.conf` sets these variables.

| Group | Variables |
|---|---|
| Product | `BOARD_PRODUCT`, `BOARD_API_HOST`, `BOARD_API_URL_ERE` |
| Tools | `BOARD_TOOL_PREFIX`, `BOARD_TOOL_MOVE`, `BOARD_TOOL_UPDATE`, `BOARD_TOOL_CREATE`, `BOARD_TOOL_COMMENT`, `BOARD_TOOL_COMMENT_EDIT`, `BOARD_TOOL_COMMENT_DELETE`, `BOARD_TOOL_GET_CARD`, `BOARD_TOOL_GET_LISTS`, `BOARD_TOOL_GET_COLUMN_CARDS` |
| Matchers | `BOARD_MATCH_MOVE`, `BOARD_MATCH_UPDATE`, `BOARD_MATCH_CREATE`, `BOARD_MATCH_COMMENT` |
| Input fields | `BOARD_IN_CARD`, `BOARD_IN_STAGE`, `BOARD_IN_BOARD`, `BOARD_IN_DESC`, `BOARD_IN_NAME`, `BOARD_IN_LABELS`, `BOARD_IN_TEXT`, `BOARD_IN_COMMENT` |
| Response fields | `BOARD_RESPONSE_ID`, `BOARD_RESPONSE_NUMBER`, `BOARD_RESPONSE_TITLE`, `BOARD_RESPONSE_BOARD` |
| State labels | `BOARD_LABEL_COLOR_<state>`, `BOARD_LABEL_NAME_<state>` |
| Ids | `BOARD_CARD_ID_ERE` |

## Hook headers

A hook that uses the board declares it, so `audit-fail-open.sh` can check the adapter's requirements and S5 can check the matchers:

```bash
# Requires: jq, curl
# Requires-Path: ../board/board.sh
# Board: required
# Board-Actions: move, update
```

## Testing an adapter

- `tests/run.sh` runs every hook against recorded board responses. A new adapter needs its own fixtures and a fake for its API.
- The contract tests in `tests/unit/` check each function on success, an empty result, an error body, and a transport failure.
- `tests/live/` runs the hooks and all five roles against a throwaway board.
