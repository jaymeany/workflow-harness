# QA Hooks

The hook-enforced constraints for the QA role. This file answers **HOW (enforcement)** — the rules the hook layer holds you to at write- and move-time, and which hook enforces each. Identity (WHO), your column, and card mechanics live in `../QA_Role.md`. The review checks live in `QA_Checks.md` (the gate and truth checks) and `QA_Surface.md` (the rendered-surface checks); the decision matrix and §9 template in `QA_Decisions.md`.

Split out of `QA_Role.md` when that file crossed the ~10K `additionalContext` cap — the seam is role identity vs. enforcement machinery.

---

## Hard Constraints

The hook layer enforces some of these; others are prose-only and depend on the agent following them. They're not optional in either case — each exists because the failure mode it prevents has cost real work.

**Comments, never description (with one tracking-card exception).** The card description is Research's evidence chain — what was found, what was decided, what's in scope. `update_card_details` replaces the description field wholesale, so any QA-side write to that field destroys Research's record even when the intent is append. QA review notes go in comments via `mcp__trello__add_comment` per the §9 QA Comment template.

The exception is tracking-card creation: QA creates tracking cards via `mcp__trello__add_card_to_list`, which writes the description at creation time. That tool is not gated. Once the tracking card exists, further description edits use comments (or are not made at all). `block-description-writes.sh` enforces the non-tracking-card case by denying any `update_card_details` call where `tool_input.description` is present.

**§9 QA Comment template required at move-time.** A move from "QA" to "Done", "Now", "Research" or "Design" requires the latest comment to be a complete §9 QA Review template variant. PASS-to-Done requires the labeled per-check sections (Run It, Service Bypass, Evidence Integrity, Security, Pipeline Invariants, Error Handling, Acceptance Criteria, Tracking Cards Created) plus a non-template body in `### Evidence Integrity`, plus an `### Iteration N Fixes Addressed` section when iteration ≥ 2. FAIL-to-Now requires `### Required Fixes`. BOUNCE-to-Research or BOUNCE-to-Design requires `### Bounce Reason` with a non-template body. Without the right artifact, the move destination contradicts the review state and the audit trail breaks. `qa-protocol-compliance.sh` enforces template format and destination match; `qa-required-fixes-coverage.sh` enforces iteration-N fix-verification continuity; `qa-freshness-check.sh` denies moves when the card has been modified since the QA comment was written.

**PASS requires evidence, not citations.** A PASS→Done move must carry a `### Verification` section showing real runtime/existence evidence — a command actually run, a portal the surface was rendered in, a row or path confirmed to exist — or an explicit, justified N/A for a card with no runtime surface. A bare `file:line` citation does **not** satisfy this: dressing code-reading in line references and calling it verified is the exact loophole that ships a green diff over a broken feature. `qa-pass-evidence-gate.sh` enforces it on `move_card`.

**Done is immutable.** Cards in "Done" are the QA-blessed final record. Editing them after the fact rewrites the audit trail of what shipped. If new scope surfaces, create a tracking card — don't edit a Done card. `gate-done-immutable.sh` enforces this on `update_card_details` (it denies the call when the target card is in "Done"). The sibling `block-description-writes.sh` covers the description-clobber concern in every other column — together the two hooks lock the audit-bearing surfaces while leaving QA free to maintain tracking-card naming and other non-description fields.

---

## Column matching

Every gate here resolves columns by **word**, not exact label: *qa*, *done*, *now*, *research*, *design*.

This is load-bearing. A gate that tests for an exact label the board does not use exits before doing any work, and the whole QA enforcement layer passes silently while appearing installed. Never reintroduce an exact-label match.

---

## References

- `../QA_Role.md` — role identity, disposition, column, card mechanics
- `QA_Checks.md` — the gate and truth checks
- `QA_Surface.md` — the rendered-surface checks
- `QA_Decisions.md` — decision matrix (PASS / FAIL / BOUNCE) and §9 comment template
- `QA_Workflow.md` — unit testing, iteration, hotfix, E2E, what NOT to flag
- `QA_Coordination.md` — card naming convention
- `../.claude/hooks/*.sh` — enforcement source
