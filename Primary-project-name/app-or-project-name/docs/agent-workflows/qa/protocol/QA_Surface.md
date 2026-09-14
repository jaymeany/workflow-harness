# QA Surface Checks

Sections 5 through 7 of the QA check set. Split out of `QA_Checks.md` when that file approached Claude
Code's ~10K-char additionalContext cap; the seam is real rather than arbitrary. `QA_Checks.md` holds the
gate and the checks about whether a claim is **true**. This file holds the checks about whether the page,
as rendered, **holds up**. Run both. Neither is optional and neither supersedes the other.

---

## 5. Site Invariants Check

**Definition**: Verify the card's changes uphold the invariants the product depends on. The project-level
constraints are in the walk-up project `CLAUDE.md` and in the code folder's `CLAUDE.md`, and those lists are
authoritative. These are the ones that hold on every card.

| Invariant | How to verify |
|---|---|
| Asset paths resolve | A path written as a literal string is not resolved for you. Check those against the built output, not the source |
| Repeated markup stays identical | Shared blocks match across every page the card touched |
| Images carry dimensions | Every `<img>` has explicit `width` and `height`. Without them the page reflows as images load |
| Motion respects the setting | Anything autoplaying or looping has a `prefers-reduced-motion` fallback |
| Focus is visible | Tab through anything interactive the card touched and confirm the focus ring shows |
| The review bar holds | **The project `CLAUDE.md` § Review bar is the single source. Read it, do not remember it.** Restating it here is how it goes stale |
| The branch model holds | **The project `CLAUDE.md` is the single source. Read it, do not remember it.** The hazard is the push to the publishing branch, not the commit |
| Nothing extra was staged | Read the commit's file list. Anything written into the code folder that `.gitignore` does not cover is one `git add .` from shipping |

### Pass/Fail

- **PASS**: all invariants hold, and you verified them by opening the page rather than by reading the diff
- **FAIL**: any violated = return to "Now"

---

## 6. Broken-State Check

**Definition**: Verify the page fails visibly rather than quietly, and that nothing is half-rendered.

What a page has instead of loud errors is failure that looks like design: a missing image renders as a gap,
a dead link renders as a link, a font that did not load renders as a fallback nobody notices. Every one of
these passes a casual look.

### Checklist

| Check | Pass Criteria |
|---|---|
| No missing assets | Network panel shows no 404. A gap where a figure belongs is the symptom |
| No dead links | Every `href` the card touched resolves. Check shared blocks that repeat across pages |
| Fonts actually loaded | The page renders in the project's fonts, not a system fallback |
| No layout shift | Reload with the cache disabled and watch. Images without dimensions are the usual cause |
| Alt text present | Every `<img>` has an `alt` that says what the image shows |
| No placeholder left behind | No lorem, no `TODO`, no `[FILL]`, no empty slot rendered as blank space |

### Pass/Fail

- **PASS**: nothing missing, nothing shifting, nothing left in
- **FAIL**: any of the above = return to "Now" with the path

The shared shape of every check above: read the effect on the rendered box, not the attribute that should
produce it, and know what your server is serving.

---


## 7. Acceptance Criteria Check

**Definition**: Verify implementation meets card requirements.

### Process

1. Read card description and acceptance criteria
2. Verify each criterion is implemented
3. Check implementation comments match card findings

### Pass/Fail

- **PASS**: All acceptance criteria met
- **FAIL**: Missing criteria = return to "Now" with specific gaps

---
