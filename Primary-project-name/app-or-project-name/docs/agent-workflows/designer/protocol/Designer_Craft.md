# Designer Craft Bar

Run this before a card leaves Design. It is the standard you are held to by yourself, because design
quality is yours. QA checks that the execution matches what you specified; it does not second-guess whether
the specification was good.

## 1. The reach order was followed

- [ ] Every value resolves to a token in the token file named in the project `CLAUDE.md`
- [ ] No literal colour, font stack, spacing or radius written into a rule
- [ ] No token invented in the diff. A missing one is named in the card instead
- [ ] Existing components reused before new ones were made
- [ ] Where hand-written CSS was unavoidable, the card says why the four prior options did not fit

## 2. The system, not the screen

- [ ] The decision generalises. Would this hold on the next three sections, or does it only work here?
- [ ] Nothing was duplicated that could have been a prop or a variant
- [ ] Two components that always appear together were merged
- [ ] The component takes data, not pre-formatted strings

## 3. Typography

- [ ] Tracking scales with size. Larger text, tighter tracking
- [ ] Leading tightens as size grows, and stops before descenders collide with the line below. Only a
      heading that WRAPS shows this, so check wrapped headings at the narrowest width in the review bar
- [ ] Measure is bounded. Nothing runs the full container width
- [ ] The eye does not reset twice in one section because two blocks sit at different measures

## 4. Rhythm

- [ ] Section padding comes from the spacing scale, never a one-off
- [ ] Vertical rhythm escalates by importance rather than being uniform
- [ ] The most important section on a page gets the most air

## 5. Motion

- [ ] Every effect answers "what does this help the user understand?" Decoration is cut
- [ ] Easing and duration come from the motion tokens. Nothing hand-typed
- [ ] Every motion component that hides content until it animates is wrapped in a guard
- [ ] `prefers-reduced-motion: reduce` set at the OS level, page reloaded, **nothing moves and nothing is missing**
- [ ] No content is gated on an animation. If the trigger never fires, the section still reads

## 6. States, which is where craft usually fails

- [ ] Hover, focus, active, disabled all designed, not defaulted
- [ ] `:focus-visible` on everything interactive, and visible on every theme the project ships
- [ ] Touch: nothing important is hover-only
- [ ] Empty, loading and error states considered where the component can have them
- [ ] Long content and short content both tested. A two-word heading and a twelve-word heading

## 7. The boring correctness

- [ ] Contrast checked against the token pair actually used, not eyeballed
- [ ] **Walked against the review bar. The project `CLAUDE.md` section Review bar is the single source.
      Read it, do not remember it.** This check does not restate it, because restated numbers go stale
- [ ] Images carry `width` and `height`
- [ ] **Borrowed line art: weight comes from SIZE, not from a stroke, unless the smallest
      feature can afford it.** Adding a stroke is safe in proportion to the SMALLEST feature, not the
      size of the icon. Check the counters at the narrowest width before believing a stroke worked
- [ ] **A decorative prop can never blank the content it decorates.** A component whose
      content survives reduced motion and a missing measurement must also survive a bad
      decoration. Drop the decoration and log; do not throw
- [ ] Where the project uses Storybook's a11y addon, it passes at `test: 'error'`
- [ ] Keyboard-only pass: tab through, nothing trapped, order matches the visual order

## 8. Every theme the project ships

**Which themes ship, and whether the user chooses, is in the project `CLAUDE.md`. Read it, do not remember
it.** The token file is where the themes are actually defined, and the Storybook toolbar switches them.

- [ ] Renders correctly on every theme that ships. Toggle each one in the toolbar
- [ ] No value assumes a theme. A hardcoded `#fff` fails here
- [ ] If the user can switch at runtime, nothing breaks *during* the switch
- [ ] Imagery holds on each. Tokens invert, a photograph does not. Say so when it does not hold

## 9. The honest look

Stop and look at it as a stranger with other tabs open.

- [ ] Would its users screenshot this?
- [ ] Does it read as considered, or as competent-and-templated?
- [ ] Is there one thing that could be removed to make it better?

If the last question has an answer, remove it and run the list again.
