# Research Cards

Card mechanics for the Research role. This file answers **HOW (cards)** — every procedural rule for assembling a card. The hooks that enforce those rules at write/move time live in `Research_Hooks.md`. Methodology lives in `Research_Protocol.md`. The messaging bus lives in `Research_Coordination.md`. Identity (WHO) lives in `../Research_Role.md`.

---

## Card Management

- Reference cards by number (e.g., `#105`).
- Prefer `mcp__trello__get_card` for individual cards. Use `mcp__trello__get_cards_by_list_id` only for explicit column scans (e.g., reviewing the state of the Research column or checking what's already in "Now").

---

## Card Description Requirements

Each item below is on the card because Dev or QA needs it to do their job. Skip items that genuinely don't apply; never substitute prose for a missing item.

- **Research findings summary** — orientation for whoever picks up the card next
- **Services discovered** (with file paths, format: `Using {Service} ({path})`) — Dev needs to know what already exists before writing new code
- **Files to modify / Files to create** — the actionable surface; without this the card isn't ready to implement
- **Dependencies** (format: `**Depends on**: #104, #107`) — drives scheduling; missing dependencies cause work-out-of-order

Two things don't belong on a research card:
- **Time estimates.** Estimates are human-hour artifacts and aren't relevant to this workflow.
- **Product strategy.** Research presents findings; the user decides what's a priority and why.

The structural gate (`gate-card-structure.sh`) enforces the file-count cap and the required sections when `## Research Complete` is declared — there is no header-allowlist check (invented-section discipline lives in `Research_Protocol.md § Pattern-recognition cues`). Read the hook's stderr if it blocks a write.

---

## Card Sizing

Split if:
- More than 3 files to modify/create
- Multiple independent features

Child cards: `#105.1 API Routes`, `#105.2 UI Components`. Mark the parent with `Children: #105.1, #105.2` and the children with `Parent: #105` so the file-count cap recognizes the split structure.

---

## Card Naming Convention

Card titles follow this format, the same for every role:

```
#<idShort> <title> <24-char card id>
```

Examples (the id shown is illustrative — always use the card's real one):
- `#12 Example Card Title 6a4d1318bfeec5789719abcd`
- `#47 Add upstream-API integration 6a4d1318bfeec578971901ef`

The card id is the card's internal 24-char `id` field (distinct from the short `idShort` the board displays) — 24 hex characters, not a name.

A trailing worktree tag is **optional**, and only useful when a board spans more than one worktree. When one is present, `gate-card-title.sh` checks it against `board_tag` in `protocol-enforcement.conf`.

---

## Handoff to Dev

The handoff is **one action: attach the green "Research complete" label.** That single gated step advances the card from the Research column to "Now" for Dev.

1. Write the description so it qualifies: `## Research Complete` marker **plus** the required sections (Services Discovered / Files / Confidence), no blocker tags, no unresolved `## Open Questions`. Description and name writes have **no** side effects — edit and review freely; nothing advances.
2. Attach the "Research complete" label (an `update_card_details` whose `labels` include the green label id, as its own call). `gate-research-complete.sh` validates the card fully qualifies and, on pass, advances it to "Now". If it doesn't qualify, the label attach is denied with the reason — fix the description and retry.

Do **not** issue a separate `move_card` to "Now" — the label is the trigger. (An explicit `move_card` is still gated by the same evaluator as a backstop.)

**Why a single trigger:** bundling label-attach + advance onto description writes meant a write blocked by one gate could still fire the advance via another separate-matcher hook — stranding a card. A label-only trigger makes the handoff one atomic, gated point, and one shared evaluator (`evaluate_research_complete` in `lib.sh`) backs both gates so structure and completeness can't diverge.

---

## Mechanical checks (hook-enforced)

Moved to `Research_Hooks.md` (loaded by its own SessionStart hook) — the hook inventory outgrew this file's context budget. Read it there.

---

## References

- `Research_Hooks.md` — the hook-enforced inventory (what fires, on what, and each hook's built-in escape)
- `Research_Protocol.md` — research methodology (tool selection, quality checks, judgment calls, pattern-recognition cues)
- `Research_Coordination.md` — messaging bus
- `../Research_Role.md` — role identity, disposition, hard constraints
- `../CLAUDE.md` — directory inventory, memory, environment, source materials
- `../.claude/hooks/protocol-enforcement.conf` — limits + board→tag map consumed by the gates
- `../.claude/hooks/*.sh` — enforcement source
