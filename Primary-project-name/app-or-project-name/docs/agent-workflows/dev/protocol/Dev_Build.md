# Dev Build

## 4. Verification

Verification is running the project and looking at the result, plus whatever checks the project `CLAUDE.md`
names, such as tests, a type-check or lint. Skipping any part of it is undetectable from the diff.

The commands are in the project `CLAUDE.md`.

### Always run, per card

**Open what you touched, and everything that links to it.** Repeated markup changed in one place leaves the
other copies inconsistent and nothing reports it.

**The review bar.** The project `CLAUDE.md` § Review bar. **Read it, do not remember it.**

**Tab through anything interactive you touched** and confirm focus is visible.

### The tokens are the bar

Token names are read by every rule and every inline SVG. **A rename breaks all of them silently.** If a card
seems to require a rename, it goes back to Research rather than being decided in the diff. A literal value
where a token exists is the same class of defect and QA treats it as one.

---

## 10. Git commit discipline

Every card's work lands in commit(s) whose subject begins with `#<card-number>`. That is what lets §6
Implementation Notes stay short: QA finds the diff with `git log --grep="#<card>"` then `git show <sha>`
instead of reading a re-narration in a comment.

**There are THREE repos. Commit in the one the card's diff belongs to.**

| Repo | Branch | Holds |
|---|---|---|
| `../../../{{CODE_DIR}}` | `{{WORK_BRANCH}}` | the code |
| `../../` (docs) | `main` | the harness and the plan |
| `../../../{{STORYBOOK_DIR}}` | `{{STORYBOOK_BRANCH}}` | the Storybook workbench, if the project has one |

The branch model for the code, from the work branch through to the publishing branch, is in the project
`CLAUDE.md` § Repos and branches.

```bash
cd <the repo the diff belongs in>
git rev-parse --show-toplevel     # must print that repo
git rev-parse --abbrev-ref HEAD   # must match the branch in the table above
git add -A
git commit -m "#<card-number> <what changed>"
```

`gate-per-card-commit.sh` searches **all three** and passes on a `#<card>` commit in any one of them. It
checks history rather than just HEAD, so batching several cards' commits is fine.

The one-shot marker is for a card that produces **no committable diff anywhere**, because the files are
gitignored or the card resolves to "no change required". It is not for anything else.

**`{{CODE_DIR}}/` is the one repo where a mistake can reach users.**

- **Commit on `{{WORK_BRANCH}}`. Never on `{{PUBLISH_BRANCH}}`.** Check the branch before every commit; the
  command is in the block above.
- **Merging toward `{{PUBLISH_BRANCH}}` follows the branch model in the project `CLAUDE.md`, and it is the
  user's call, not a card's.**
- `git add -A` stages anything you left in that directory. **Look at what you staged before you commit.**
