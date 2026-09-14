# CLAUDE.md: {{WORKSPACE_NAME}}

This is the workspace file. Every agent session started anywhere below this folder loads it.

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

| Project | Folder | What it is |
|---|---|---|
| {{PROJECT_NAME}} | `app-or-project-name/` | {{PROJECT_SUMMARY}} |

Each project has its own `CLAUDE.md`, and that file governs the project.

## Why the folders are shaped this way

The folder names describe what goes in them.

- `Primary-project-name/` is the **workspace**: the folder that holds one or more projects and this file.
- `app-or-project-name/` is **one project**: the code, the docs, and the agents that work on it.

Claude Code reads every `CLAUDE.md` from the folder a session starts in, up through its parent folders. Each
agent starts in its own folder under `docs/agent-workflows/`, so every agent loads this file, the project
file, the docs file, and its own. That is how one set of rules reaches every agent without being copied.

```
Primary-project-name/                  the workspace. This file.
└── app-or-project-name/               one project. Its CLAUDE.md.
    ├── <code folder>/                 the code. Its own git repo.
    ├── <Storybook folder>/            the Storybook workbench, if the project has one.
    └── docs/                          CLAUDE.md. Everything that is not code.
        ├── handoffs/                  session handoffs, one per role per day
        └── agent-workflows/
            ├── orchestrator/          one Claude Code session per folder
            ├── research/
            ├── designer/
            ├── dev/
            └── qa/
```

The folder structure stays, but you can rename `Primary-project-name/` and `app-or-project-name/`, and add
projects or folders. No hook uses those two names. The hooks find folders by their position: they look three
levels up from an agent's folder for the project, and they look for `docs`, `handoffs` and the role folder
names. Keep those names and that depth as they are.

Rename a folder only while no agent is running inside it. Then start the agent again from the new path, and
update the folder names in this file and the project `CLAUDE.md`.

## Naming new folders

- **A new project** gets a copy of `app-or-project-name/` next to the first one, renamed for the project.
  Use lowercase letters and hyphens. Add a row to the Projects table above.
- **The code folder** inside a project is named during first start and recorded in the project `CLAUDE.md`.
  Use the repository's name, in lowercase with hyphens.
- **New folders inside `docs/`** can be named for what they hold, such as `planning/`. Do not rename
  `handoffs/` or `agent-workflows/`.
