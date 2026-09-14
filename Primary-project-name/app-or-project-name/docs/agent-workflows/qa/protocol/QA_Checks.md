# QA Checks

## 0. Run it and look at it (gate, runs before everything else)

**The gate is that the pages render.** A card whose page does not load is not reviewable.

Run the project with the command in the project `CLAUDE.md`.

Open the page the card touched **and every page that links to it**. Repeated markup changed in one place
leaves the other copies inconsistent and nothing reports it.

If a page 404s, a figure resolves to nothing, or the stylesheet fails to load, the card fails. Return it
to "Now" with the path. Do not proceed to any other check.

**Dev claims of "it renders" are informational, not verification.** The verification is you opening it in
your own session and citing what you saw. See `QA_Workflow.md` §10.

## 0b. Files First

Card descriptions are the dev's interpretation of their own work, not ground truth. False positives
(flagging non-existent issues) and false negatives (missing real bugs) both come from reviewing the
description instead of the file.

### Before every review

1. **Read the changed files.** `Read` every file the card touches.
2. **Trace context.** `grep -rn "<token-or-class>" ../../../{{CODE_DIR}}/` and `git diff`. To find consumers
   of a symbol, match the import (`grep -rn "^import.*<Symbol>"`), not the name: a filename match counts
   files that only mention it in a comment.
3. **Verify claims.** The card description is a starting hypothesis, not the truth.
4. **Make the check fail once.** For any check whose output is a count, a coverage claim or an
   emptiness, run it against a case that should fail before citing it. If it cannot fail, it is not a
   check. State what it does not see alongside what it found.


### Before flagging an issue

1. **Read the file.** Confirm the issue exists in it, not in the card narrative.
2. **Search documentation.** Find the standard being violated (the project `CLAUDE.md`, the code folder's
   `CLAUDE.md`, `Dev_Standards.md` anti-patterns).
3. **Cite the source.** Specific doc and line number.

A flagged issue with no doc citation is a style preference, not a finding. See §15.

---

## 1. Token Compliance Check

**Definition**: Verify every value comes from the token file named in the project `CLAUDE.md` rather than
being written as a literal into a rule.

### Source of Truth

The token file named in the project `CLAUDE.md`. Read it on every review, verify each value used has a
token, and FAIL a literal.

| What to check | Bypass that must FAIL |
|---|---|
| Color | A hex, `rgb()` or named color in a rule where a token exists |
| Font | A font stack written into a rule instead of the font token |
| Layout | A width or padding literal where a layout token exists |
| Inline SVG | `fill`/`stroke` hardcoded instead of reading `var(--...)` or `currentColor` |
| A new token | A token invented in the diff to avoid surfacing that one was missing |

**The last row is the one that matters most.** A missing token is supposed to surface in Implementation
Notes so it gets added deliberately. A token quietly invented mid-card is how two names for one value
enter the system, and nothing raises.

### Pass/Fail

- **PASS**: every value resolves through a token
- **FAIL**: any literal or any invented token = return to "Now"

---

## 2. Security Check

**Definition**: Verify the change leaks nothing and reaches nothing it should not.

### Checklist

| Check | Pass Criteria |
|---|---|
| No secrets in the output | No key, token or internal URL left in code, a comment or an attribute |
| External requests are allowed ones | Every request to another host is one the project `CLAUDE.md` allows |

### Pass/Fail

- **PASS**: nothing leaked, and every external request is allowed
- **FAIL**: a secret in the output, or a request the project does not allow = return to "Now" with the location

---

## 3. Content Integrity Check

**Definition**: Verify that nothing in the change claims something the record does not support.
**This is the most important check here.** A layout bug is embarrassing. A false claim does more damage.

### Checklist

| Check | Pass criteria |
|---|---|
| Claims clear the boundaries | Every factual claim checked against the project `CLAUDE.md` § Boundaries |
| Numbers trace | Any figure traces to a source the project names. A number written to sound right is the worst defect available here |

### Pass/Fail

- **PASS**: every claim traces
- **FAIL**: any unsupported claim = return to "Now". Say which claim and what failed to support it

---

## 5 onward: the rendered-surface checks

Sections 5 (Site Invariants), 6 (Broken State) and 7 (Acceptance Criteria) live in `QA_Surface.md`,
loaded by its own hook. They are the checks you run against the page as rendered, rather than against the
claims it makes. Split out of this file when it approached the additionalContext cap.
