# CLAUDE.md: {{PROJECT_NAME}}

This is the project file. Every agent on this project loads it. Role docs point here for anything specific
to the project, so it is the single source for the values below.

The orchestrator fills in the values in double curly braces during first start. If any remain and you are
not the orchestrator, do no work and tell the user to start the orchestrator first.

## What this is

{{PROJECT_SUMMARY}}

Built with {{STACK}}.

## Where the parts live

```
app-or-project-name/
├── CLAUDE.md                  this file
├── {{CODE_DIR}}/              the code. Its own git repo.
├── {{STORYBOOK_DIR}}/         the Storybook workbench, if the project has one.
└── docs/                      everything that is not code
    ├── CLAUDE.md
    ├── handoffs/
    └── agent-workflows/       one folder per role
```

A `CLAUDE.md` inside `{{CODE_DIR}}/` sits beside `docs/`, not above it, so it does not load on its own. Roles
read it by name.

## Repos and branches

| Repo | Folder | Agents commit to | Remote |
|---|---|---|---|
| Code | `{{CODE_DIR}}/` | `{{WORK_BRANCH}}` | {{CODE_REMOTE}} |
| Docs | `docs/` | `main` | {{DOCS_REMOTE}} |
| Workbench | `{{STORYBOOK_DIR}}/` | `{{STORYBOOK_BRANCH}}` | {{STORYBOOK_REMOTE}} |

**Branch model for the code:** {{BRANCH_MODEL}}

The publishing branch is `{{PUBLISH_BRANCH}}`. What a push to it does: {{PUBLISH_EFFECT}}

Agents commit on `{{WORK_BRANCH}}`. Merging toward `{{PUBLISH_BRANCH}}` and pushing is the user's call, never a
card's.

Push rules in the hooks: Dev may push. The Orchestrator and Designer hooks block every push. Every hook that
guards pushes blocks `git push --force` without `--force-with-lease`.

## Commands

{{COMMANDS}}

## Plan

- **The plan:** `{{PLAN_FILE}}`. What gets built, and the build sequence. The orchestrator keeps it current.
- **The open decisions list:** `{{DECISIONS_FILE}}`. Decisions only the user can make.

## Standards

- **Token file:** `{{TOKEN_FILE}}`. Every color, font, spacing value and type size comes from it.
- **Component folders:** {{COMPONENT_FOLDERS}}
- **Component library:** {{COMPONENT_LIBRARY}}

## Service registry

{{SERVICE_REGISTRY}}

QA maintains the service registry, if the project has one.

## Test suite

{{TEST_SUITE}}

QA writes and maintains the test suite, if the project has one.

## Review bar

{{REVIEW_BAR}}

This section is the only place the review bar is written. Role docs point here.

## Boundaries

{{BOUNDARIES}}

QA checks every change against this list before a card reaches Done.

## Trello

Board: {{TRELLO_BOARD_NAME}}, ID `{{TRELLO_BOARD_ID}}`

The hooks read the board through `docs/agent-workflows/board/`. That folder holds
the board id in `board.conf` and the Trello adapter in `adapters/trello/`. To use
a different board, write an adapter for it and name it in `board.conf`. See
`board/CONTRACT.md`.

| Column | List ID | Owner |
|---|---|---|
| Next | `{{LIST_ID_NEXT}}` | Backlog. No role watches it |
| Research | `{{LIST_ID_RESEARCH}}` | Research |
| Design | `{{LIST_ID_DESIGN}}` | Designer |
| Now | `{{LIST_ID_NOW}}` | Dev. Only Research moves cards here |
| QA | `{{LIST_ID_QA}}` | QA |
| Done | `{{LIST_ID_DONE}}` | QA moves cards here on PASS |

The orchestrator has no column. It works across the whole board.

The hooks find each column by a word in its name: `research`, `design`, `now`, `qa`, `done`. A list renamed
without its word takes that role offline without an error.

The hooks match labels by color: green for Research complete, blue for Needs research, red for a QA FAIL,
purple for QA complete, orange for a QA tracking card.

Card titles, for every role: `#<idShort> <title> <24-character card id>`. A trailing worktree tag is optional.

## Storybook

Folder `{{STORYBOOK_DIR}}`, port {{STORYBOOK_PORT}}. The Designer builds surfaces here and runs the Storybook
server.

## Tools

{{TOOLS}}
