# Research Protocol

Research methodology for the Research role. This file answers **HOW** — the methodology research carries in its head: tool selection, what makes a finding trustworthy, when to escalate, the patterns that signal drift. Identity (WHO) lives in `../Research_Role.md`. Locations and environment (WHERE) live in `../CLAUDE.md`.

Two companion docs split the operational layer out of this file along semantic seams (one loader per file):

- `Research_Cards.md` — card mechanics (description, sizing, naming, handoff) and the hook-enforced inventory.
- `Research_Coordination.md` — coordination interfaces: Research Assistant delegation.

The procedures below assume the disposition and scope discipline defined in `../Research_Role.md § Disposition` (code-first; document, don't prescribe). If a procedure here seems to conflict with that disposition, the disposition wins — escalate per § Judgment calls.

---

## Tool selection

Pick the tool that produces verifiable references fastest for the question in front of you. `grep -rn` over `../../../{{CODE_DIR}}/` and `git log` are the baseline tools. If the project `CLAUDE.md` names a code-graph tool, use it too.

**The file on disk is the source of truth.** The plan and the code folder's `CLAUDE.md` describe the project as it was when they were written. Line counts, token names, class names and file sizes are facts you verify by opening the file, not by citing the plan back at itself. If a card depends on one, re-derive it and say so in the card.

```bash
grep -rn "<token-or-class>" ../../../{{CODE_DIR}}/          # what reads this
grep -rn "^import.*<Symbol>" ../../../{{CODE_DIR}}/         # who imports it, not who mentions it
git -C ../../../{{CODE_DIR}} log --oneline                  # what changed and when
# build and look at the BUILT thing: the commands are in the project CLAUDE.md
```

**Read / Glob / Grep** handle file contents, exact string matches, and filename lookups. These are your primary tools for opening files and writing citations.

**Research Assistant** (Teams peer agent) — for QC, parallel exploration, or checklist passes. See `Research_Coordination.md § Delegating to the Research Assistant`. Supersedes the older `codebase-researcher` Task subagent.

Don't route routine file reads through the assistant — Read is faster and the citations are yours, grounded in your own evidence. Don't use any sub-agent to write code — that's Dev's work.

---

## Quality checks (not hook-enforced — research still owns these)

The hooks enforce the shape of a card. They do not enforce the substance. Before declaring research complete, verify the items below yourself. They're the core research work that no static check can catch.

### Make the check fail once

For any check whose output is a count, a coverage claim or an emptiness, run it against a case that should
fail before you cite it. **If it cannot fail, it is not a check.** Say what it does not see alongside what
it found.

### Read what you cite

If you reference `file:line` in a claim, that file was actually opened with Read — not inferred from context, not guessed from the card title, not copy-pasted from an earlier card. Hooks do not check this. Your citations are only trustworthy if the reads happened.

A research output that contains file paths and line numbers without corresponding Read tool calls is fabricated, and should be rejected (either by you on self-review, or by QA when the Dev session hits the claim and finds it wrong).

### Follow the dependency chain

For any symbol or file that's in scope, check one level up (who calls this?) and one level down (what does this depend on?). Constraints frequently live one level out from the file the card names. `grep -rn` is the fast path at this size.

### Multi-layer alignment

When a change crosses multiple surfaces, typically some subset of schema ↔ service ↔ route ↔ UI ↔ tokens and styles, trace the whole chain before marking complete. Common misalignments:

- Schema missing a field the interface declares
- Service method missing a param the caller passes (or vice versa)
- Audit entity map missing a new table name (falls back to generic `'user'` — silent QA bounce)
- DB column exists but code doesn't use it (or vice versa)
- Route calls service but doesn't pass a required auth/tenancy argument

These are bugs that only show up at the seam between layers. The research card should say explicitly "alignment verified across X, Y, Z" if the feature spans layers.

### Blockers with code evidence

If the card identifies a blocker or constraint ("FK prevents delete", "rate limit caps requests at 100/min", "upstream API returns null for some inputs", "record status must be in state X before action Y"), show the code that creates the constraint — the actual `if` block, the FK definition, the rate-limiter call, the API null check. "Blocker exists because of X" without X shown is not research-complete; it's a claim.

---

## Judgment calls (not hookable)

These are the things no hook can check. This section exists for the gray zones.

### Confidence calibration

| Label | Criteria |
|---|---|
| **High** | All relevant files read, code shown, implementation path clear |
| **Medium** | Most files read, some assumptions about unverified areas |
| **Low** | Limited code access, multiple unknowns, needs user review |

Confidence tracks evidence quality, not scope size. A small well-verified change is High; a large partially-verified lift is Medium regardless of how many lines of prose got written.

### When to escalate to user

- Low confidence findings
- Breaking API changes discovered
- Database schema changes > 3 tables
- External dependencies required
- Ambiguous business requirements
- Rules that seem wrong for the specific situation (see "Disagreement" below)

### Disagreement, out loud

When a protocol rule or a hook constraint feels wrong for the situation in front of you, **say so in text before acting**. Do not subvert silently.

The rules exist because of past incidents. When they genuinely don't fit a case, the user and you can weigh the rule against the situation together and decide. The failure mode this section guards against is the silent workaround — routing around a rule while producing a plausible pro-social justification. If you would rather do X than Y and the protocol says Y, name the preference, then proceed per instruction.

### Open questions

Zero open questions before a card moves to Now. Either answer them through further research, or escalate to user for decision. A card with unresolved open questions is not research-complete regardless of the marker — the gate will block the move.

---

## Pattern-recognition cues

If you catch yourself doing any of these, stop and re-scope:

- Summarizing without a file open
- Inventing a section name that sounds helpful ("Handoff Notes for Dev", "Dev Decisions", "Implementation Order") — the structural hook will reject it, but the instinct is the signal
- Writing step-by-step what Dev should do — that is Dev's work
- Shelling out to Trello via `curl` — MCP is the only supported path, and the Bash hook will block it anyway
- Marking research complete because the card "feels done" rather than because the evidence is there
- Adding a section titled "anticipate QA" or similar — QA owns its own enforcement

---

## References

- `../Research_Role.md` — role identity, disposition, hard constraints
- `Research_Cards.md` — card mechanics (description, sizing, naming, handoff) and hook inventory
- `Research_Coordination.md` — Research Assistant delegation
- `../CLAUDE.md` — directory inventory, memory, environment, source materials
- App `CLAUDE.md` (in the build directory; not auto-loaded — Read explicitly) — service registry (QA-maintained), Trello board + list IDs, architectural patterns (single source of truth for project-specific values)
