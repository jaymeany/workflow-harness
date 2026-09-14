# CLAUDE.md: {{PROJECT_NAME}} docs

Everything for the project that is not code. The project file one folder up covers the project as a whole.

The orchestrator fills in the values in double curly braces during first start. If any remain and you are
not the orchestrator, do no work and tell the user to start the orchestrator first.

## Git

{{DOCS_GIT}}

QA manages the docs repo.

Never run `git add -A` from the docs root. Several agent sessions share this tree, and a broad add stages
their files too. Add files by name.

## What is in here

- `handoffs/`. Session handoffs. Each role writes one before its context is compacted.
- `agent-workflows/`. One folder per role. Each is where that role's Claude Code session starts.
- The plan and the open decisions list, if the user keeps them here. The project `CLAUDE.md` § Plan says
  where they are.

## Handoff naming

`<role>-handoff-YYYY-MM-DD.md`, in `handoffs/`. The handoff hook blocks compaction until today's file
exists.
