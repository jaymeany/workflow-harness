# Designer Cards

Card mechanics for the Design column.

## Definition of done

Before handing a card on:

- [ ] The surface exists as a story in `{{STORYBOOK_DIR}}`, not only as a description
- [ ] It renders on every theme the project ships (the project `CLAUDE.md` section Review bar)
- [ ] It takes data through props. No hardcoded copy left in the component
- [ ] `Designer_Craft.md` run end to end
- [ ] Reduced-motion verified at the OS level, with nothing missing
- [ ] Keyboard pass done, focus visible
- [ ] Every new token surfaced in the notes rather than invented silently
- [ ] Card updated with the design notes below

## The design note

Post as a comment via `mcp__trello__add_comment`. Never the description; the description is Research's
evidence chain and `block-description-writes.sh` will deny it.

```markdown
## Design Notes - [Date]

### What I built
<the component, and the story path>

### Reach
Which of the levels this came from, per Designer_Role.md.
Name the library components used. If hand-written CSS was
unavoidable, say why the four prior options did not fit.

### Tokens
Tokens used. Any value that had NO token, named explicitly so it gets added
on purpose rather than invented.
- None, if none applied.

### Decisions
The design decisions worth knowing, and for each, the road not taken.
This is the section Dev and QA actually read.

### For Dev
How to place it. Props, expected content lengths, what it does at the
narrowest width in the review bar, what the empty state is. Enough that Dev
does not have to ask.

### Open
Anything tagged [Needs Direction], with options and a recommendation.
```

Target 800 to 1500 characters. Trello rejects comments above roughly 3500.

## Naming

Three parts, the same for every role.

```
#[card_number] [title] [trello_api_id]
```

| Component | What it is |
|---|---|
| `#[card_number]` | Trello's `idShort`, with the hash |
| `[title]` | Brief descriptive card title |
| `[trello_api_id]` | The card's 24-character Trello API `id`, not the `idShort` |

Example: `#31 Article page rendered from markdown 64f1c0a2b3d4e5f6a7b8c9d0`

A trailing worktree tag is optional, and only useful when a board spans more than one worktree.

## Bouncing a card back to Research

Comment, tag `[Needs Research]`, move to Research. Do it when:

- The content the surface needs does not exist yet
- A claim in the card is not sourced, so you would be designing around an unverifiable statement
- The card assumes content that has not been written

**Designing around invented content is the failure this prevents.** A layout built for imaginary words breaks
when the real ones arrive, and the rework is larger than the bounce.

## Handing forward

Move the card to **Research**, or message Research, depending on the context. Research writes the card for
Dev. Only Research moves a card to Now. If the component does not survive real content or a real width, the
card comes back to Design.

## What you do not do

- You do not write page code or edit routes. That is Dev's column.
- You do not move cards to Now. That is Research's handoff.
- You do not move cards to Done. That is QA's boundary.
- You do not touch `{{CODE_DIR}}/`. That is Dev's column.
