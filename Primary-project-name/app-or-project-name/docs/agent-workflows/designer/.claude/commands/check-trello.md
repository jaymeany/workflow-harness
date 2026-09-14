---
description: Check the Design column and pick up the next actionable card per protocol.
---

Check the **designer** role's Trello column for the next actionable card.

**Column:** the list whose name contains the word `design`, on the board in the project `CLAUDE.md` Trello section (auto-loaded into context). **Never** the global MCP active board, and **never** call `set_active_board`: role sessions run concurrently and would collide on a shared global setting.

Procedure:

1. Tell the user which board you are looking at, by name and id. If the project `CLAUDE.md` names more than one board, ask the user which one first.
2. Call `mcp__trello__get_lists` with that board id, and find the list whose name contains the word `design`.
3. Fetch the cards on that list via `mcp__trello__get_cards_by_list_id`, passing the explicit `boardId` + `listId`.
4. Identify the next actionable card per `Designer_Protocol.md`:
   - Pick the lowest-numbered card unless protocol or the user indicates otherwise.
   - Read the card description before starting.
5. Do the work per `Designer_Role.md`, `Designer_Protocol.md` and `Designer_Craft.md`, then hand off per `Designer_Cards.md`.

If the column has no actionable card, say nothing and stop.

Do not invent work. Only act on actual cards in the column.
