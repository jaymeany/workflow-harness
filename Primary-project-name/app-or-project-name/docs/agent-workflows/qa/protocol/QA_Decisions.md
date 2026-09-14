# QA Decisions

## 8. Decision Matrix

| Confidence | Criteria | Action |
|------------|----------|--------|
| 100% | All checks pass, all findings tracked | Move to "Done" |
| 90-99% | Minor concerns, no blockers | Hold, notify user for decision |
| <90% | Any check fails | Move to "Now" with detailed issues |
| n/a | Spec ambiguity / acceptance criteria malformed / lift source missing | Bounce to "Research" with **Status**: BOUNCE |
| n/a | The gap is in the design of the surface | Bounce to "Design" with **Status**: BOUNCE |

**Bounce vs. FAIL**: FAIL means "Dev's implementation does not meet the spec." BOUNCE means "the spec itself is broken and Dev cannot meet it as written." Bouncing returns the card to Research, not to Dev. Use it when the acceptance criteria are ambiguous, contradict another card, omit a required surface (e.g., Archive without Show Archived), or when a port-from-upstream card has no resolvable upstream source. Do NOT use BOUNCE as an escape hatch when Dev shipped something wrong — that's still FAIL → Now.

**Zero-findings gut check**: If you complete all checks with zero findings and zero tracking cards, stop and ask yourself: "Did I actually try to break this, or did I just verify the happy path?" Re-read the changed files one more time looking specifically for: edge cases with null/undefined input, error paths that swallow failures, adjacent code that the changes interact with, and pre-existing issues in files the dev touched. If you still find nothing, that's a legitimate clean PASS — but it should be rare.

### Findings Tracking

Untracked observations during review become buried "minor notes" that never make it onto the board — they vanish from session memory, never get prioritized, and become tomorrow's incidents. Every finding that surfaces during a review gets a Trello card in "Research" before the card can PASS.

A card cannot move to Done with untracked observations. Either:
1. **Create a tracking card** for the gap/finding, then PASS
2. **FAIL the card** if the finding is blocking

Examples of findings that require tracking cards:
- Unhandled webhook event types
- Missing validation for edge cases outside the card's scope
- Hardcoded values or temporary flags that need future cleanup
- Unrelated bugs discovered during review
- Integration sync edge cases not covered

"Non-blocking note," "minor gap," and "future work observation" are the three phrases that mean "this finding is about to disappear." If a finding is real, it gets a card.

**Every tracking card gets the orange "Tracking" label.** Apply it to the card as part of card creation. Tracking cards usually land in "Research" (so Research picks them up in the next pass) but can be placed in "Now" when the finding needs immediate attention.

### Escalate to User

- Architectural concerns beyond card scope
- Breaking changes to existing APIs
- Data integrity risks
- Ambiguous requirements

### Return to "Now"

- Build failures (type-check, lint, or tests)
- Service bypass violations
- Security vulnerabilities
- Silent failures
- Missing acceptance criteria
- Data integrity violations

### Bounce to "Research"

- Acceptance criteria ambiguous or contradictory
- Card ships a partial surface that requires a paired surface not yet specced (Archive without Show Archived, Approve without Reject, etc.)
- Port-from-upstream card with no resolvable upstream source
- Spec contradicts another card already in Done
- Dev was forced to invent because the card didn't tell them what to build

### Bounce to "Design"

- The gap is in the design of the surface, not in the spec or the implementation

QA does not ask the user product questions. Bouncing routes the gap to Research, which owns the PRD and is the only role that escalates spec ambiguity to the human.

---

## 9. QA Comment Format

**Comment length.** Trello rejects `add_comment` payloads above roughly 3,500 characters with
HTTP 414. Nothing enforces this, so keep comments under it yourself. If a comment would exceed it, put the detail in the commit message
or a file and cite it from the comment. A 414 loses the whole comment, not the excess.

Three variants — one per move destination. The Status field and the destination must agree; the qa-protocol-compliance hook denies the move otherwise.

### PASS variant (move to "Done")

```markdown
## QA Review - [Date]
**Iteration**: [1/2/3]
**Status**: PASS

### Run It: [PASS / N/A]
- type-check: [PASS / N/A]
- lint: [PASS / N/A]
- tests: [PASS / N/A] ([X] passed)

### Service Bypass Check: [PASS / N/A]
- [Details]

### Evidence Integrity: [PASS / N/A]
- [Either "No registry changes required for this card" OR "Registry updated at {file:line} to reflect {change}" OR "#<n> tracking card created for deferred update"]

### Security Check: [PASS / N/A]
- [Details]

### Pipeline Invariants: [PASS / N/A]
- [Details]

### Error Handling: [PASS / N/A]
- [Details]

### Acceptance Criteria: [PASS]
- [Details]

### Iteration N Fixes Addressed (required when **Iteration** > 1):
1. [Required Fix 1 from prior FAIL]: verified at file:line — [explanation]
2. [Required Fix 2 from prior FAIL]: verified at file:line — [explanation]

### Tracking Cards Created:
- [#cardNumber - Brief description of gap/future work] (or "None")

### Done Well:
- [Positive observations]
```

### FAIL variant (move to "Now")

```markdown
## QA Review - [Date]
**Iteration**: [1/2/3]
**Status**: FAIL

### Run It: [PASS / FAIL]
- type-check: [PASS / FAIL]
- lint: [PASS / FAIL]
- tests: [PASS / FAIL] ([X] passed)

### [other check sections, marking PASS / FAIL / N/A as appropriate]

### Required Fixes:
1. [Issue with file:line reference]
2. [Issue with file:line reference]

### Tracking Cards Created:
- [#cardNumber - ...] (or "None")
```

### BOUNCE variant (move to "Research" or "Design")

```markdown
## QA Review - [Date]
**Iteration**: [1/2/3]
**Status**: BOUNCE

### Bounce Reason
[Required, non-template prose. Explain what makes the spec — not the implementation — unworkable. Examples: "Acceptance criteria require an Archive button but no Show Archived surface is specced; QA cannot verify a half-loop." / "Port-from-upstream card #N references upstream symbol X which doesn't exist at the cited path." / "Acceptance criterion 3 contradicts what shipped in #M (Done)."]

### Acceptance Criteria Gap
- [What the card asks for]
- [What's missing or contradictory]
- [What Research needs to resolve before Dev can implement]

### Tracking Cards Created:
- [#cardNumber - ...] (or "None" — the bounce itself is the routing signal)
```

---
