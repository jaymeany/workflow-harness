# QA Coordination

## Card Naming Convention

Inconsistent card names break board-wide search and lookup. The same card shows up under different names in different searches, idShort drift slips through, and tracking cards QA creates stand out from the rest of the board. Every card name follows this format:
```
#[card_number] [title] [trello_api_id]
```

| Component | Example |
|-----------|---------|
| `#[card_number]` | `#12` (Trello's idShort, just an illustration) |
| `[title]` | Brief descriptive card title |
| `[trello_api_id]` | The card's 24-character Trello API ID (Trello's internal `id` field, distinct from `idShort`) |

**Example format** (illustrative; substitute real values when naming an actual card):
`#12 Example Card Title 64f1c0a2b3d4e5f6a7b8c9d0`

**Three parts. There is no fourth field.** `enforce-card-naming.sh` tolerates a trailing suffix but does
not require one.
