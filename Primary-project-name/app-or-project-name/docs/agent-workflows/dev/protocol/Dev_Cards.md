# Dev Cards

## 5. Definition of Done

Before moving card to "QA":

- [ ] All acceptance criteria implemented
- [ ] **It runs.** What you touched, run and opened, plus everything that links to it
- [ ] **Review bar walked.** The project `CLAUDE.md` section Review bar is the single source; read it, do not remember it
- [ ] Standards in the project `CLAUDE.md` followed. Registered services used through their entry points; no literal where a token exists
- [ ] Keyboard focus visible on anything interactive you touched
- [ ] **Card's diff lives in commit(s) on `{{WORK_BRANCH}}` whose subject begins with `#<card-number>`** (see below)
- [ ] Card updated with implementation notes
- [ ] TodoList cleaned up

**The two failures that matter most here.** A second copy of something the project already has, such as a
service or a token, and work committed to `{{PUBLISH_BRANCH}}`. The first drifts silently and shows up months
later as inconsistency nobody can source. The second skips the branch model. Neither raises an error.

**Per-card commit discipline.** Every card's work lands in commit(s) in `{{CODE_DIR}}/` on `{{WORK_BRANCH}}`
whose subject lines begin with `#<card-number>`. This
makes the diff for any card findable via `git log --grep="#<n>"` and lets
QA pull the per-card change with `git show <sha>` instead of reverse-
engineering it from HEAD. Most cards land in a single commit; §8 (Partial
Completion) governs multi-commit cases. Do not squash one card's commits
into another's; do not bury one card's diff inside an unrelated commit.
This discipline is what allows §6 to drop Files Modified and Adjacent
card context — the diff is in git, not the comment.

---

## 6. Card Update Format

**Comment length.** Trello rejects `add_comment` payloads above roughly 3,500 characters with
HTTP 414. Nothing enforces this, so keep comments under it yourself. If a comment would exceed it, put the detail in the commit message
or a file and cite it from the comment. A 414 loses the whole comment, not the excess.

Before moving to "QA", post a comment to the card via `mcp__trello__add_comment` containing the §6 template below. Implementation Notes go in comments — never the description (the description is Research's evidence chain; `block-description-writes.sh` will deny description writes).

The diff lives in git per §5's per-card commit discipline; the comment is
*signals only* — what services were used, what was tested, where
implementation diverged from the research card, and any QA hand-off
context the diff doesn't carry. QA finds the diff via
`git log --grep="#<card>"` then `git show <sha>`.

`gate-implementation-notes.sh` checks this template on the move to QA: the `## Implementation Notes` header,
at least one real bullet under `### Services Used`, at least one completed `- [x]` line under
`### Testing Done`, and a `### Deviations from Research` header.

```markdown
## Implementation Notes — [Date]

Commit: `<sha>` (optional pointer for QA convenience; the
`git log --grep="#<card>"` lookup also works)

### Services Used
- <registered service, shared module or token this card used, with its path>
- None, with a one-clause reason, if the card used none

### Testing Done
- [x] <what you ran, and the result>
- [x] Opened what you touched, plus everything linking to it
- [x] Review bar walked

### Deviations from Research
<one paragraph if implementation diverged from the research card, or
literal "None" if it didn't>
```

**What this template intentionally drops:**
- **Files Modified** — `git show <sha> --stat` already provides this. Re-typing it in the comment is bytes without signal.
- **Adjacent card context** — obsolete under per-card commit discipline. The commit IS the card boundary.

**Length constraint:** Trello's `mcp__trello__add_comment` rejects payloads
above ~3500 characters with HTTP 414.
Draft Implementation Notes targeting ~800–1500 characters. The new
template makes that easy — when it doesn't, the cause is record-style
prose in Services / Testing / Deviations, not section count. Compress
prose; don't enumerate the diff.

---

## 7. Clarification Protocol

Triggered whenever Dev cannot proceed without upstream input. Two flavors:

**A. Research is inaccurate or stale.** File path doesn't exist, line number doesn't match, claimed constraint isn't real, service mentioned isn't registered, etc.

**B. Card surfaces a decision Dev shouldn't make alone.** Research did its job but explicitly defers a product / design / architecture call to "Dev to weigh." Examples: pixel-perfect-vs-framework-widget tradeoffs on auth surfaces, route shapes that depend on a sibling card's resolution, copy that references a feature not yet decided. The fact that Research flagged the question is the signal — the question goes back, it does not get answered inline.

Both flavors produce the same action: comment, tag, move to Research. Research either answers themselves (flavor A is usually their fault to fix) or escalates to the user / design (flavor B usually needs that). When the answer lands, the card moves back to Now.

### Step 1: Document the Issue

Add comment to card:

**Flavor A — research vs. code discrepancy:**

```markdown
## Clarification Needed - [Date]

### Issue
Research states line 104 carries a specific rule, but the current file at
line 104 is different:
\`\`\`css
/* different from what the card describes */
\`\`\`

### Questions
1. Was the file changed since research?
2. Should I proceed against the current structure?
```

**Flavor B — open Dev decision Dev shouldn't make:**

```markdown
## Clarification Needed - [Date]

### Open questions for Research / upstream

1. <decision the card defers to "Dev to weigh">
   - Path A: <one-sentence summary + tradeoff>
   - Path B: <one-sentence summary + tradeoff>
   - Recommendation: <Path A or B + why>
2. <ancillary asks the card surfaces but doesn't resolve>

Cannot proceed until these resolve.
```

The recommendation is optional but useful — if Research / design / user agrees with it, the resolution is one word ("Path B"); if they don't, they say what to do instead.

### Step 2: Move

Move the card to "Research" via `mcp__trello__move_card`. The
`apply-needs-research-label.sh` PreToolUse hook auto-applies the blue
"Needs research" label on the move — Dev does not need to apply it
manually.

**Dev does not retitle cards.** The blue label is the flag, not the
card name. Renaming the card is a Research-surface action, not a Dev
action. Dev's three card actions are: comment, label (via the hook on
move), and move.

### Step 3: Wait

Research re-researches (or escalates) and moves the card back to "Now" with the resolved scope. Pick the next card from Now in the meantime.

---

## 8. Partial Completion

When blocked mid-implementation:

### Step 1: Commit Working Code

```bash
git add .
git commit -m "#<card> Partial - <what works>, <what's blocked> pending"
```

The `#<card>` prefix is required even on partial commits — `gate-per-card-commit.sh` checks the latest commit's subject regardless of whether the work is partial or complete, and §5's per-card commit discipline applies uniformly.

### Step 2: Update Card

```markdown
## Partial Completion - [Date]

### Completed
- <what works>
- <what shipped>

### Blocked
- <what's blocked and why>

### Remaining
- <what's left>
```

### Step 3: Tag and Move

1. Add `[Partially Complete - Blocked]` to card name
2. Move to "Now" column
3. Add comment explaining the blocker

---

## Documentation differs from research

If implementation diverges from research, update the card with reasoning and flag `[Docs Need Update]`. QA picks up the flag.

---

## Card Management

- Reference cards by number
- Default to `mcp__trello__get_card` for individual cards. Use `mcp__trello__get_cards_by_list_id` only when you need a column's contents (e.g., scanning Now for the next pickup).

---

## Card Naming Convention

All cards MUST follow this format, the same for every role:
```
#[card_number] [title] [trello_api_id]
```

| Component | Example |
|-----------|---------|
| `#[card_number]` | `#12` (Trello's `idShort`) |
| `[title]` | Brief descriptive card title |
| `[trello_api_id]` | The card's 24-character Trello API ID (Trello's internal `id` field, distinct from `idShort`) |

Example: `#12 Example Card Title 64f1c0a2b3d4e5f6a7b8c9d0`

Three parts. A trailing worktree tag is optional, and only useful when a board spans more than one worktree.
