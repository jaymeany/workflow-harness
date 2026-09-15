# Research Hooks

The hook-enforced inventory for the Research role. This file answers **HOW (enforcement)** — which hooks fire, on what, and what escape each one already encodes. Card mechanics (description, sizing, naming, handoff) live in `Research_Cards.md`. Methodology lives in `Research_Protocol.md`. Coordination lives in `Research_Coordination.md`. Identity (WHO) lives in `../Research_Role.md`.

Split out of `Research_Cards.md` when that file crossed the ~10K `additionalContext` cap — the seam is card-authoring rules vs. enforcement machinery.

---

## Mechanical checks (hook-enforced)

Structural rules for research cards are enforced by hooks in `.claude/hooks/`, configured via `protocol-enforcement.conf`. The hooks are authoritative — the descriptions below are the inventory; the scripts are the source of truth. Each hook encodes a user-intent, and where it has an override or fail-open that escape is part of the intent — read a hook's override before treating a block as a wall.

### PreToolUse

- `gate-research-complete.sh` — the handoff trigger. On `update_card_details` that **attaches the green "Research complete" label**: validates the card qualifies (marker + required sections + no blocker tags + no unresolved `## Open Questions`, via the shared `evaluate_research_complete` in `lib.sh`) and, on pass, advances the card to "Now"; denies the label attach if it doesn't qualify. A content-only `update_card_details` (description/name, no label) has **no** label or advance side effect — that's the decoupling that prevents the strand-a-card trap. On `move_card` to "Now": gated by the same evaluator as a backstop.
- `gate-card-structure.sh` — on `update_card_details` / `add_card_to_list` / `move_card`: file-count cap (>3 files across "Files to Modify" + "Files to Create" requires a `Parent:` / `Children:` reference) and required sections when `## Research Complete` is declared (Services Discovered/Verified gap, Files/Acceptance, Confidence — the same set `lib.sh` checks). Rules sourced from `protocol-enforcement.conf`. (Does **not** enforce a header allowlist, despite older docs — only the file-cap and required-section checks.)
- `gate-column-scope.sh` — on `update_card_details`: enforces the Hard Constraint that Research writes only to cards currently in the Research column. Fetches the card's `idList`, looks up the list name, and denies if `is_research_column` (lib.sh) doesn't match — i.e. if the name doesn't contain the word *research*. **Exception:** a "Now" card may take a description-only strict append headed `## Research Addendum`, so Dev reads corrections in context at pickup. QA/Done stay blocked. Fails open on missing tools/env/api.
- `gate-description-append-only.sh` — on `update_card_details` when `tool_input.description` is set: fetches the current description and denies the write unless the new description contains the current description as a substring (i.e., it's a strict append). Backstops the Hard Constraint that the card description is the work history; wholesale replacement would wipe it. Fails open on missing env/api. **Override:** also fails open (allows a full rewrite) while the card is still in the Research column — an in-column correction isn't a wipe, so the gate only re-engages after handoff. A clean rewrite of an in-column card needs no workaround; just write it.
- `deny-trello-comments.sh` — on `add_comment` / `update_comment` / `delete_comment`: denies all board comment writes. Backstops the Hard Constraint that Research findings go in the description, not comments.
- `deny-direct-trello-api.sh` — on `Bash`: rejects `curl`/`wget` to `api.trello.com`. Forces board operations through `mcp__trello__*` so the other hooks fire.


### PostToolUse

- `apply-research-complete-label.sh` — on `add_card_to_list`: best-effort attach of the green "Research complete" label when the new card's description already qualifies. Closes a gap PreToolUse can't cover (card doesn't exist yet).

### SessionStart

- `load-research-role.sh` — preloads `Research_Role.md` into `additionalContext`.
- `load-research-protocol.sh` — preloads `protocol/Research_Protocol.md` into `additionalContext`.
- `load-research-cards.sh` — preloads `protocol/Research_Cards.md` into `additionalContext`.
- `load-research-coordination.sh` — preloads `protocol/Research_Coordination.md` into `additionalContext`.

Two further SessionStart hooks load *state*, not docs, and are excluded from the digest (their size varies with inbox/board contents):

- `load-agent-comms.sh` — states that peers are reached with `ListAgents` and `SendMessage`, that there is no bus, and that the board column watcher is the only Monitor to arm.
- `load-research-trello-catchup.sh` — emits the column-matching rule and instructs the session to arm the **board column watcher** Monitor. The hook makes no board call; the watcher finds the Research list id on its first poll.

Arm the board column watcher Monitor as your first action each session. It is the wake signal for new cards; do not replace it with a `/loop` polling command.

One loader per file, split semantically (identity / methodology / cards / coordination). Claude Code's `additionalContext` caps around ~10K chars per hook; over-cap content is persisted to disk and substituted with a small preview, so keeping each file under the cap means each loader inlines its doc in full. `load-status-digest.sh` runs last in `SessionStart` and reports OK or WARN; a WARN means a file crossed the cap and the fix is a further semantic split, never byte-range slicing inside a loader.

### PreCompact

- `precompact-write-handoff.sh` — matcher `manual|auto`, **both** paths. Blocks unless `handoffs/research-handoff-YYYY-MM-DD.md` exists for today **and** was written within the last 60 minutes; surfaces a structured stderr prompt inlining the required handoff sections (or a shorter "refresh" prompt when the file is merely stale). Manual `/compact` is gated too: the context-wall freeze path ends in a manual compact, which was the one ungated door. Freshness exists because existence alone let a morning handoff satisfy an evening compaction. Sweep-safe — writes nothing, references no other handoff file, fails open on missing `$CLAUDE_PROJECT_DIR`, missing handoffs dir, or an unstattable file. Human escape hatch when the session is out of context: `touch` the handoff and re-run `/compact`.

When a hook fires, the error message tells you exactly what failed and why. No need to memorize the details — the hooks will surface them when relevant.
---

## References

- `Research_Cards.md` — card mechanics (description, sizing, naming, handoff)
- `Research_Protocol.md` — research methodology (tool selection, quality checks, judgment calls, pattern-recognition cues)
- `Research_Coordination.md` — messaging bus
- `../Research_Role.md` — role identity, disposition, hard constraints
- `../CLAUDE.md` — directory inventory, memory, environment, source materials
- `../.claude/hooks/protocol-enforcement.conf` — limits + board→tag map consumed by the gates
- `../.claude/hooks/*.sh` — enforcement source
