---
description: Check the QA column and pick up the next actionable card per protocol.
---

Check the **qa** role's Trello column for the next actionable card.

**Column:** the list whose name contains the word `qa`. **Board:** the board id in the project `CLAUDE.md` Trello section (auto-loaded into context). **Never** the global MCP active board, and **never** call `set_active_board`: role sessions run concurrently and would collide on a shared global setting.

Procedure:

1. Tell the user which board you are looking at, by name and id. If the project `CLAUDE.md` names more than one board, ask the user which one first.
2. Resolve the column's list id by name (dynamic — list ids may rotate): call `mcp__trello__get_lists` with that explicit `boardId` and find the list whose name contains the word `qa`.
3. Fetch the cards on the resolved list via `mcp__trello__get_cards_by_list_id`, passing the explicit `boardId` + `listId`.
4. Identify the next actionable card per the methodology in `protocol/`:
   - Pick the lowest-numbered card unless protocol or the user indicates otherwise.
   - Read the description (Research's evidence chain) AND the latest §6 Implementation Notes comment from Dev before starting review.
5. Do the review per `QA_Role.md` and `protocol/`. The existing hook layer (done immutability, description-write block, §9 template at move-time, freshness check, required-fixes coverage, deferral-phrase surfacer, post-move queue surfacing) enforces the rules — you don't have to remember them.

If the column has no actionable card, say nothing and stop.

Do not invent work. Only act on actual cards in the column.
