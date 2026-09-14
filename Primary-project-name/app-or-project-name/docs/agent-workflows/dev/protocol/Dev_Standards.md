# Dev Standards

## 2. Implementation Standards

### What the stack is

The stack, the token file and the project's standards live in the project `CLAUDE.md` and in the code
folder's own `CLAUDE.md`. Read them before the first card.

A script, a dependency or a build tool the stack already uses is simply the stack. None of that gets bounced
to Research.

### Tokens are the registry

The token file named in the project `CLAUDE.md` is the registry for visual values. **Every color, font,
spacing value, type size and stroke weight comes from it.**

A literal in a rule is the same defect a second copy of a shared service is: it drifts, it differs by one
character, and nothing raises.

- If a value you need has a token, use the token.
- If it has no token, **surface it. Do not improvise one.** Say so in Implementation Notes and let the
  token get added deliberately.
- Inline SVG reads the same tokens through `fill`, `stroke` and `currentColor`. Text inside SVG does not
  inherit page font settings, so set `font-family` and `font-size` explicitly on the SVG or its text nodes.

**What is a finding: a token that restates a value another token already carries.** Two names for one number
drifts the moment one moves.

**Read the comment block above a token before citing it.** The reason a value is what it is often lives
there rather than in the declaration.

### The contracts

Token names are binding. A rename breaks every rule and every inline SVG that reads it, silently and
everywhere at once. Where the plan defines a token name, quote it exactly. If a card seems to need a rename,
bounce it to Research rather than deciding it in the diff.

### Determinism

- Images carry explicit `width` and `height`. Without them the page reflows as they load.
- Anything that moves respects `prefers-reduced-motion`.

### Errors

**Fail loudly. Never ship a page half-rendered.** If a page you touched does not render, or a figure
resolves to a missing file, that is reported with the path and the reason. A broken image that renders as
a gap looks like a design choice to everyone who did not write it.

Check the paths you wrote. A path written as a literal string is not resolved for you, and it can go missing
silently.

---

## 9. Anti-Patterns

### DO NOT

- **Hardcode a value that has a token**, or invent a token to avoid surfacing that one is missing.
- **Commit on `{{PUBLISH_BRANCH}}`.** See `Dev_Build.md` §10.
- **Relax a verification check.** If the review bar says every page, every page means every page.

### DO

- Run the project and open what you touched, plus everything that links to it, before handing off.
- Walk it against the review bar. The project `CLAUDE.md` § Review bar is the single source; read it, do
  not remember it.
- Tab through anything interactive you touched and confirm focus is visible.
- Put the reason in the report. QA reads them.
- Commit with `#<card-number>` leading the subject, on `{{WORK_BRANCH}}`.
