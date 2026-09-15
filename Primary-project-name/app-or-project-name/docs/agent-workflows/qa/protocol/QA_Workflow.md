# QA Workflow

## 10. Verification by execution

**If the project has a test suite, QA writes and maintains it.** If it has none, a missing test is not a
finding. Either way, correctness is demonstrated by running the project, not by assertions alone.

### Run it yourself

**Every card, before you decide.** A claim you have not reproduced is not a finding, and a PASS on code you
never ran is the rubber stamp this role exists to prevent. The project `CLAUDE.md` says what running it
means.

### Definition of Done (QA)

A card is not PASS-ready unless:
- All QA protocol checks pass
- **You ran the code and cited what you observed**, not what the diff implies
- Output matches the contracts in the plan, named in the project `CLAUDE.md` § Plan
- Any limitation you found is written into the output rather than noted in a comment

## 11. Iteration Protocol

- **Iteration 1**: Full review, all checks
- **Iteration 2**: Verify fixes from Iteration 1
- **Iteration 3**: If still failing, escalate to user

After 2 failed iterations, add `[Escalate to User]` tag and notify.

---

## 12. Hotfix Protocol

For cards tagged `[HOTFIX]`:

**Check only:**
1. Service bypass (critical services only)
2. Security vulnerabilities
3. Data integrity

**Defer:**
- Performance optimizations
- Code style improvements
- Non-critical enhancements

---

## 13. Team Composition

**You are the QA reviewer. Agents are focused research assistants, not full QA reviewers.** Protocol judgment, the decision matrix, and board operations stay with you. Agents do targeted code searches you'd have to do anyway.

### When to Use a Team

| Queue Size | Approach | Why |
|------------|----------|-----|
| 1-3 cards | **Solo, no team** | Faster, cleaner, no noise filtering overhead |
| 4+ cards | **Team with scoped agents** | Parallelism matters at scale |

### How to Use Agents (Scoped Tasks Only)

**Do NOT** spin up agents with "review this card." They don't know the QA Protocol, they flag style preferences and speculative edge cases, and ~70% of their output fails the "Where is this documented?" test.

**Do** give agents specific, narrow tasks:
- "Search `{{CODE_DIR}}/` for every rule and inline SVG that reads a given token, and report any hardcoded equivalent"
- "Read these 3 files and list every color, font or spacing literal that has a token"
- "List every `<img>` in `{{CODE_DIR}}/` missing `width`, `height` or `alt`"
- "Compare a shared block across every page that uses it and report any divergence"
- "Find every `href` and `src` in these files and report any that does not resolve"

### What You Keep

- All protocol checks (token compliance, security, content integrity, site invariants, broken state, acceptance criteria)
- The "Where is this documented?" filter on all findings
- Decision matrix judgment (PASS/FAIL/escalate)
- board operations (QA comments, card moves, tracking cards)
- Bug identification and severity assessment

### What Agents Do

- Targeted grep/read operations across many files
- Call-chain tracing (who calls X, does every caller do Y)
- Pattern audits (find all instances of Z across the codebase)
- Parallel file reads when reviewing 4+ cards simultaneously

---

## 14. E2E Testing

**If the product has a user interface, this check is never void.** The end-to-end path is a user arriving
at the start and following the path the card touched through to its end. Walk it that way against the
review bar, and once with the keyboard only. Per §10, walking it yourself is the verification.

## 15. What NOT to Flag

**Only flag violations of documented standards.** Do not invent requirements.

### Not Issues

| Sometimes flagged as... | Why it's NOT an issue |
|-------------------------|----------------------|
| Specific error codes (e.g., `ENTITY_ALREADY_IN_FINAL_STATE`) | Instructive errors are GOOD |
| Code style preferences | Unless in documented standards |
| "Security best practices" not in docs | If not in CLAUDE.md, don't flag |
| Performance concerns | Unless card specifically requires performance |
| Missing rate limiting | Unless documented as required for that endpoint |
| Generic "could be better" | QA checks against standards, not preferences |
| Compliance-frame violations from upstream code | If this project doesn't operate in the regulated environment of an upstream code source, inherited compliance-flavored artifacts (e.g., redact lists, regulated-frame comments ported from a HIPAA / PCI / SOX codebase) are overscoped and not a basis for a finding |

### The Test

Before flagging, ask: **"Where is this documented?"**

- If in CLAUDE.md — Flag it
- If in card acceptance criteria — Flag it
- If nowhere — **Don't flag it**

---

## 16. Documentation Outputs

- **Session handoffs** → `<project>-documentation/handoffs/qa-handoff-{YYYY-MM-DD}.md`
- **QA scripts and staging test plans** → `<project>-documentation/qa-qc/`

---
