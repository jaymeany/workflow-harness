# Dev Protocol

Implementation standards for the Dev role.

**Core Principle**: Research tells you WHAT and WHERE. CLAUDE.md tells you HOW. QA checks that you did it right.

This file answers **HOW** — the implementation methodology Dev carries: pre-implementation checklist, recipes, code patterns, build verification, definition of done, card update format, clarification, partial completion, anti-patterns, git push. Identity (WHO) lives in `Dev_Role.md`. Locations and environment (WHERE) live in `CLAUDE.md`.

---
---

## CRITICAL: Read the project files first

Before writing ANY code you must know the rules in three places:

- **The project `CLAUDE.md`** (walk-up). The repos, the branch model, the board, the boundaries, the stack.
- **`{{CODE_DIR}}/CLAUDE.md`** (sibling, off the walk-up, read it explicitly), if the code folder has one.
  The code's own conventions.
- **`Dev_Standards.md`**. The token rule, the anti-patterns.

## 1. Pre-Implementation Checklist

Before writing ANY code:

### Step 1: Read the Research Card

- [ ] Read full card description
- [ ] Note confidence level (green/yellow/red)
- [ ] Identify all files to modify
- [ ] Understand the business case

### Step 2: Verify Research Findings

```
Read <path/to/file.ts>
```

Check that:
- [ ] Files exist at stated paths
- [ ] Line numbers match current code
- [ ] Constraints/blockers are accurate
- [ ] Services mentioned actually exist

If research is inaccurate:
1. Add comment to card with discrepancies
2. Add `[Needs Clarification]` tag
3. Move card back to "Research"
4. Do NOT guess or proceed with wrong information

**Read directly, or spawn an Explore agent?** When the files to verify are
named in the card and total fewer than five, Read them directly — spawning
an agent for a known small set is overhead. When the card scope is uncertain
or you need to find existing patterns across the codebase, spawn one
Explore agent and let it do the search. Multiple Explore agents only when
the searches are genuinely independent and parallel saves wall time.


### Step 3: Read the token file

The token file named in the project `CLAUDE.md`. Read it before writing a rule. Every color, font, spacing
value, type size, stroke weight and diagram color comes from there. A literal in a rule is the defect this
file exists to prevent: it drifts, it differs by a shade, and nothing raises.

If the value you need has no token, **surface it in Implementation Notes rather than inventing one.**

### Step 4: Impact Check

Before changing a shared rule or a token, find what reads it:

```bash
grep -rn "<token-or-class>" ../../../{{CODE_DIR}}/
grep -rn "^import.*<Symbol>" ../../../{{CODE_DIR}}/   # consumers, not mentions
```

Match the import, not the name. If the callers fall outside the card's scope, flag to Research for
re-scoping rather than widening the card.

**Token names are the blast radius that matters.** A rename breaks every rule and every inline SVG that
reads it, silently and everywhere at once. If a card requires a rename, it goes back to Research.

### Step 5: Plan with TodoWrite

Create task list for the implementation:

```
TodoWrite([
  { content: "<task from card>", status: "pending" },
  { content: "Run the project, open what you touched + everything linking to it", status: "pending" },
  { content: "Walk the review bar", status: "pending" },
])
```

---

## References

- `Dev_Role.md`. Role identity, voice, disposition, hard constraints
- `Dev_Standards.md`. The token rule, anti-patterns
- `Dev_Build.md`. Verification and git commit discipline
- `CLAUDE.md`. Startup reads, hooks, memory, environment, handoffs
- `{{CODE_DIR}}/CLAUDE.md`. The code's own conventions
