---
description: Check the board, or a list or card the user names, and frame or route what is there.
---

Check the Trello board for the **orchestrator**. The orchestrator has no column of its own.

**Board:** the board id in the project `CLAUDE.md` Trello section (auto-loaded into context). **Never** the global MCP active board, and **never** call `set_active_board`: role sessions run concurrently and would collide on a shared global setting.

Procedure:

1. Tell the user which board you are looking at, by name and id. If the project `CLAUDE.md` names more than one board, ask the user which one first.
2. If the user named a list or a card, fetch that: `mcp__trello__get_cards_by_list_id` for a list, `mcp__trello__get_card` for a card, passing the explicit `boardId`.
2. Otherwise, call `mcp__trello__get_lists` with the board id and review the board against the standing checks in `Orchestrator_Cards.md`.
3. Frame, split, tag or route per `Orchestrator_Cards.md` and `Orchestrator_Protocol.md`.

If nothing needs action, say so in one line and stop.

Do not invent work. Only act on actual cards, or on steps in the plan.
