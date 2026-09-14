# Designer Protocol

How a card becomes a surface. Identity lives in `../Designer_Role.md`. The bar lives in
`Designer_Craft.md`. Locations live in `../CLAUDE.md`.

## 1. Before you design

1. **Read the card.** Research should have attached the evidence and the content. If the content the surface needs is missing, tag `[Needs Research]` and bounce it. Designing around invented content produces a layout that breaks when the real content arrives.
2. **Read the section in the plan.** The plan, named in the project `CLAUDE.md` § Plan, says what the section is for and what it contains. It is not a suggestion.
3. **Open Storybook.** `cd ../../../{{STORYBOOK_DIR}} && npm run storybook`. Look at what already exists before adding to it.

## 2. Visualize first

This is the whole reason the workbench exists. **Render, screenshot, look, iterate, then reason about data
and logic.** Not the other way around.

```
1  Build the surface in a story with hardcoded, realistic content
2  Screenshot it. Look at it as a stranger
3  Iterate in the workbench, not in a page
4  Only when it holds up, extract the props and make it take data
5  Then hand it to Dev to place in a route
```

Realistic content means the real content where it exists, and text of a realistic length where it does
not. A component that only looks right with three-word headings is not finished.

## 3. Reach, in order

Never start with hand-written CSS. See `../Designer_Role.md` for the full order.

```
token  ->  existing component  ->  new library primitive  ->  other project libraries  ->  new token  ->  CSS
```

Check what a new component drags in first. A background effect is not worth 400KB unless it is doing real
work.

## 4. Wrap the motion

Every motion component that hides content until it animates goes through a guard. Raw, such components set
`opacity: 0` on load and animate in on a scroll trigger, so a trigger that never fires leaves the section
blank with no error.

Two rules that follow:

- **Content is never gated on an animation.** If JS fails, the trigger misses, or hydration is slow, the section still reads.
- **`prefers-reduced-motion` wins.** Not "reduces to a shorter animation". Renders plainly.

## 5. Judgment calls

**When the plan and your taste disagree**, the plan wins on *what the section is*, you win on *how it
looks*. If you think the section itself is wrong, that is Orchestrator's call, so raise it rather than
redesigning around it.

**When a surface needs a decision the user has not made**, tag `[Needs Direction]` and say what the options are
and what you would pick. Do not guess past an open decision. Which decisions are open is in the open
decisions list, named in the project `CLAUDE.md` § Plan, not in this file.

**When you cannot hit the bar with what exists**, say so in the card with the specific gap. A surface that
ships below the bar with nobody noticing is worse than a card that comes back.

## 6. Before handoff

Run `Designer_Craft.md` end to end. Then write the handoff per `Designer_Cards.md` and hand the card to
**Research**, or message Research, depending on the context.

Dev should be able to place your component without a question. If they have to ask how it behaves at a
narrow width or what the empty state does, the card was not finished.
