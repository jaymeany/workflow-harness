# CLAUDE.md: {{WORKSPACE_NAME}}

This is the workspace file. A workspace is a folder that holds one or more projects, such as the software
of one company. One team of agents works on the projects in it. Every agent loads this file, so it is the
single source for the values below.

The orchestrator fills in the values in double curly braces during first start. If any remain and you are
not the orchestrator, do no work and tell the user to start the orchestrator first.

## Purpose

{{WORKSPACE_PURPOSE}}

## Owner

{{OWNER_NAME}}. {{OWNER_ROLE}}

When a role doc says "the user", it means {{OWNER_NAME}}. A decision outside a role's own domain goes to the
user. Agents surface decisions. They do not make them.

## Rules for all work here

{{WORKSPACE_RULES}}

## Projects

Every agent can work on every project here.

| Project | Folder | What it is |
|---|---|---|
| {{PROJECT_NAME}} | `{{CODE_DIR}}/` | {{PROJECT_SUMMARY}} |

In the role docs, `<project>` means the folder of the project a card works in, from this table. A card can
touch more than one.

Each project folder is its own git repo. Its `CLAUDE.md`, if it has one, sits beside `docs/`, not above it,
so it does not load on its own. Read it by name before you work in that project.

There is one section below for each project. Copy the section for every project you add.

### {{PROJECT_NAME}}

Folder `{{CODE_DIR}}/`. Built with {{STACK}}.

**Repo and branches.** Remote: {{CODE_REMOTE}}. Agents commit on `{{WORK_BRANCH}}`. The publishing branch is
`{{PUBLISH_BRANCH}}`. What a push to it does: {{PUBLISH_EFFECT}}

**Branch model:** {{BRANCH_MODEL}}

**Commands:** {{COMMANDS}}

**Standards.**
- Token file: `{{TOKEN_FILE}}`. Every color, font, spacing value and type size comes from it.
- Component folders: {{COMPONENT_FOLDERS}}
- Component library: {{COMPONENT_LIBRARY}}

**Storybook.** Folder `{{STORYBOOK_DIR}}/`, port {{STORYBOOK_PORT}}, branch `{{STORYBOOK_BRANCH}}`, remote
{{STORYBOOK_REMOTE}}. The Designer builds surfaces here and runs the Storybook server.

## Where the parts live

```
{{WORKSPACE_NAME}}/
├── CLAUDE.md                  this file
├── <project>/                 one folder per project. Each is its own git repo
└── docs/                      everything that is not code. Its own git repo
    ├── CLAUDE.md
    ├── handoffs/
    └── agent-workflows/       one folder per role. One team for every project
```

## Repos and pushes

The docs repo is `docs/`. Agents commit to `main`. Remote: {{DOCS_REMOTE}}

Each project's repo and branches are in its section above. Agents commit on the project's work branch.
Merging toward its publishing branch and pushing is the user's call, never a card's.

Push rules in the hooks: Dev may push. The Orchestrator and Designer hooks block every push. Every hook that
guards pushes blocks `git push --force` without `--force-with-lease`.

## Plan

- **The plan:** `{{PLAN_FILE}}`. What gets built, and the build sequence. The orchestrator keeps it current.
- **The open decisions list:** `{{DECISIONS_FILE}}`. Decisions only the user can make.

## Service registry

{{SERVICE_REGISTRY}}

QA maintains the service registry, if the workspace has one.

## Test suite

{{TEST_SUITE}}

QA writes and maintains the test suite, if the workspace has one.

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

The orchestrator has no column. It reads the whole board and routes cards to Next, Research or Design.

The hooks find each column by a word in its name: `research`, `design`, `now`, `qa`, `done`. A list renamed
without its word takes that role offline without an error.

The hooks match labels by color: green for Research complete, blue for Needs research, red for a QA FAIL,
purple for QA complete, orange for a QA tracking card.

Card titles, for every role: `#<idShort> <title> <24-character card id>`. A trailing worktree tag is optional.

## Tools

{{TOOLS}}

## Why the folders are shaped this way

A workspace holds one or more projects. The agents live in its docs repo, beside the projects, so they
work on the projects in this workspace. A new project placed here, beside the others, gets the same agents,
rules and board. A project kept somewhere else does not.

Claude Code reads every `CLAUDE.md` from the folder a session starts in, up through its parent folders. Each
agent starts in its own folder under `docs/agent-workflows/`, so every agent loads its own file, the docs
file, and this one. That is how one set of rules, and the list of every project, reaches every agent
without being copied.

You can rename this folder and add projects or folders. No hook uses this folder's name. The hooks find
folders by their position: they look three levels up from an agent's folder for this one, and they look for
`docs`, `handoffs` and the role folder names. Keep those names and that depth as they are.

Folders above this one can be anything, such as a folder for each company you work with.

Rename a folder only while no agent is running inside it. Then start the agent again from the new path, and
update the folder names in this file.

## Naming new folders

- **A new project** is a new folder in this one, beside `docs/`. Use the repository's name, in lowercase with
  hyphens. Add a row to the Projects table, a section for it, and its folder name to `REPO_NAMES` in
  `docs/agent-workflows/dev/.claude/hooks/gate-per-card-commit.sh`. The same agents work on it. Do not copy
  the agents.
- **New folders inside `docs/`** can be named for what they hold, such as `planning/`. Do not rename
  `handoffs/` or `agent-workflows/`.
