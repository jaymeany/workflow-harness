---
description: Check the Research column and pick up the next actionable card per protocol.
---

Check the **research** role's Trello column for the next actionable card.

**Column:** the Research column — whichever list on the board has the word *research* in its name. Match on the word, never on the full label: the column gets relabeled and the role should survive it. This mirrors `is_research_column` in `.claude/hooks/lib.sh`, which the gates use. **Board:** the board id in the project `CLAUDE.md` Trello section (auto-loaded into context). **Never** the global MCP active board, and **never** call `set_active_board`: role sessions run concurrently and would collide on a shared global setting.

Procedure:

1. Tell the user which board you are looking at, by name and id. If the project `CLAUDE.md` names more than one board, ask the user which one first.
2. Resolve the column's list id by name (dynamic — list ids may rotate): call `mcp__trello__get_lists` with that explicit `boardId` and find the list whose lowercased name **contains the word `research`**.
3. Fetch the cards on the resolved list via `mcp__trello__get_cards_by_list_id`, passing the explicit `boardId` + `listId`.
4. Identify the next actionable card per `protocol/Research_Cards.md`:
   - Skip cards already labeled "Research complete".
   - Skip cards with `[Needs User Approval]` or `[Needs Clarification]` tags in the description.
   - Prefer the lowest-numbered actionable card unless your protocol or the user has indicated otherwise.
5. Do the research per `Research_Role.md` and `protocol/` (`Research_Protocol.md` for methodology, `Research_Cards.md` for card mechanics, `Research_Coordination.md` for talking to Dev and QA). The existing hook layer (column scope, structural gates, append-only writes, research-complete labeler/auto-advance) enforces the rules — you don't have to remember them.

If the column has no actionable card, say nothing and stop.

Do not invent work. Only act on actual cards in the column.

---

**This command running is explicit user intention.** Whether fired by a cron loop or a direct `/check-trello` invocation, the user is telling you: research the cards in your column. That is the contract.

Failure modes — each is a failure, not a safety move:

- Ignoring a card in the list because it "feels" out of scope.
- Asking the user whether a card should be researched.
- Flagging cards and waiting for direction instead of researching.
- Stopping work on a card mid-research to seek permission.
- Inventing skip conditions beyond the four below.
- Treating body-content phrases ("Why tracked, not blocking", "tracking-only", etc.) as gates. They are research input, not stop signals. The ONLY body-content self-defer is an explicit `## Status` section that says "held" / "deferred."

If a card turns out to be wrong scope, the user moves it, the hook layer rejects it, or Dev returns it with `[Needs Clarification]`. Those are the corrections. Your asking is not.

---

**Skip / surface conditions** (the complete list — no others exist):

1. Green "Research complete" label → skip.
2. `[Needs User Approval]` tag in description → skip.
3. `[Needs Clarification]` tag in description → skip.
4. **Unambiguously out-of-scope QA tracking card** → raise it to the user, do not advance.

Condition 4 is narrow on purpose. It applies when ALL of:

- The card is a tracking card (orange `Tracking` label, "Discovered by" / "Surfaced during QA review" framing, "Why tracked, not blocking" rationale).
- The card's scope is orthogonal to the current product focus in a way no reasonable read could miss — e.g., the plan's current focus is one part of the product and the card refactors an unrelated part.
- If you find yourself reasoning about whether it qualifies, it does NOT qualify — research it.

Surface format when condition 4 fires: one-line flag naming the card and the orthogonality. Do not draft research. Do not move the card. Wait for the user to direct.
