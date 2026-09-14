# Research Build Context

## What is being built, and where your cards come from

**The plan, named in the project `CLAUDE.md` § Plan, is the whole build.** Read it before your first card.
Your job is not to invent scope. It is to turn each numbered step into a card whose description carries
enough evidence that Dev can implement it without asking a question.

Where that plan defines binding names, such as tokens and the class names more than one rule reads,
**quote them into the card rather than paraphrasing.** A paraphrase that drifts by one character breaks
every consumer that reads it, silently and everywhere at once.

**Verify claims against the file, do not cite the plan back at itself.** The plan and the code folder's
`CLAUDE.md` describe the project as it was when they were written. If a card depends on a line count, a
token name or a file size, re-derive it from `../../../{{CODE_DIR}}/` and say in the card that you did.

**Claims need a source.** The project `CLAUDE.md` § Boundaries says what may and may not appear. A claim you
cannot source does not go in a card.
