# Orchestrator Cards

How to write a card each role can start from, and how to keep the board honest.

## Card template

Written into the **description**, which is yours to author for a new card. Once a card is in flight,
Research owns the evidence chain in the description; add comments after that.

```markdown
## Outcome
<what is true when this is done. Not the task, the result.>

## For
<Research | Design | Dev>  ->  enters <column>

## What exists already
- <path> <what it gives you>
- <path> <what it gives you>

## Out of scope
- <the thing this card is not, so it cannot grow into it>

## Depends on
- <card, or "nothing">

## Open decisions touched
- <none, or name them. If any, this card is NOT ready to route.>
```

## Sizing

A card is one outcome for one role. If two roles must both act, it is two cards with a dependency.

Too big: "Build the settings page." Three roles, unwritten requirements, two open decisions.
Right: "Add the display-name field to the existing settings form, using the validation rule in the plan."
One role, one outcome, names its source.

## Naming

`#<idShort> <title> <24-character card id>`

Three parts, the same for every role. A trailing worktree tag is optional, and only useful when a board
spans more than one worktree.

## The columns

| Column | Owner | Means |
|---|---|---|
| Next | Orchestrator | Framed, not yet routed |
| Research | Research | Gathering evidence and sources |
| Design | Designer | Building the surface in Storybook |
| Now | Dev | Building it into a route |
| QA | QA | Verifying the execution |
| Done | QA | Passed |

Hooks resolve columns by **substring**, not exact label. **Do not rename these lists.**

## Standing checks each session

- [ ] Anything sitting in one column for more than a couple of sessions. Ask why, in a comment
- [ ] Anything in `Next` that is actually blocked. Tag it `[Needs Decision]` and name which one
- [ ] Any card whose scope has grown. Split it
- [ ] Any card that contradicts the plan. Either the card is wrong or the plan is stale; resolve it, do not leave both
- [ ] Handoffs from the last session of each role, in `docs/handoffs/`

## Escalating to the user

Escalate, do not decide, when:
- A card is blocked on one of the open decisions in the open decisions list
- Two roles disagree inside a domain neither owns
- The plan's sequence turns out to be wrong in a way that changes scope
- A commercial question appears. Pricing, offers, what to publish

State the decision, the options, what each costs, and what you would pick. Then wait. **Nothing on the
user's list gets guessed past**, however small it looks.
