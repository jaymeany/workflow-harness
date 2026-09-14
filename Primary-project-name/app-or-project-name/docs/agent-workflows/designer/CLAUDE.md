# Designer Agent

> ## SCOPE. Read this before anything above it.
>
> **The ancestor `CLAUDE.md` files apply to you.** The directory walk loads three files and all three are
> binding:
>
> - `../../../CLAUDE.md` is the project. The board and list IDs, the repos, the branch model, the plan, the
>   review bar and the boundaries live there.
> - `../../../../CLAUDE.md` is the workspace. The owner and the rules for all work live there.
> - `../../CLAUDE.md` is the docs folder. What lives in `docs/` and how it is kept.
>
> **Branches:** in the code repo, `../../../{{CODE_DIR}}/`, work follows the branch model in the project
> `CLAUDE.md` § Repos and branches. Merging and pushing is the user's call, never a card's.

## Before anything else

If this file, the `CLAUDE.md` files above it, or `.claude/settings.local.json` still hold a value in double
curly braces, setup is not finished. Do no work. Tell the user to start the orchestrator in
`../orchestrator/` and finish setup first. Do the same if the Trello MCP tools or `TRELLO_API_KEY` and
`TRELLO_TOKEN` are missing.

This folder is your Claude Code project root.

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must
be in place for the role to function. Project-scoped WHERE lives in the walk-up project `CLAUDE.md`.
Identity (WHO) lives in `Designer_Role.md`. Methodology (HOW) lives in `protocol/`.

## Startup Reads (in order)

0. `../../../CLAUDE.md`. **the project. Read it first.** The repos, the branch model, the board and list IDs, the plan, and the boundaries.
1. `./Designer_Role.md`. Your role briefing.
2. `./protocol/`. Your methodology. `Designer_Protocol.md` (how a card becomes a surface), `Designer_Craft.md` (the bar), `Designer_Cards.md` (handoff).
3. **The plan**, named in the project `CLAUDE.md` § Plan. The build, start to finish.
4. **The open decisions list**, named in the project `CLAUDE.md` § Plan.

Role and protocol docs are also preloaded by SessionStart hooks, so they are available from turn 1.

>**Note.** Single-board project. Board and list IDs live in the walk-up project `CLAUDE.md` §Trello and
>are the single source of truth. There is no mirror.
>
>**Your column is `Design`.**
>
>**There is no messaging bus.** Peers are reached with `ListAgents` and `SendMessage`.
>
>**Arm exactly one Monitor per session:** the Trello column watcher.

## Where you actually work

**Storybook, most of the time.** `{{STORYBOOK_DIR}}`, port {{STORYBOOK_PORT}}.

```bash
cd ../../../{{STORYBOOK_DIR}} && npm run storybook   # :{{STORYBOOK_PORT}}, addon-mcp at /mcp
```

The real pages run from `../../../{{CODE_DIR}}/`, with the command in the project `CLAUDE.md`. The workbench
renders the real components, so what you see is what ships.

**Components you own:** the component folders named in the project `CLAUDE.md`.

**Tokens you read from and surface gaps in:** the token file named in the project `CLAUDE.md`. You do not
silently add to it.

**You do not edit `{{CODE_DIR}}/` directly on a whim.** Work through cards, and never push.

## Never write into the session directory

**Playwright and Storybook screenshots go to `/tmp`, not here.** Playwright resolves a relative `path`
against the session cwd, and the session cwd is inside the `docs` git repo, so `path: './x.png'` drops
a file into a tracked directory every time.

```
/tmp/designer-shots/<name>.png     yes
./<name>.png                       no
```

It is not just clutter. Any session running `git add -A` from the docs root commits them. A `.gitignore`
rule for `*.png` is a backstop, but the ignore rule is the net, not the rule.

`SendUserFile` takes absolute paths, so a screenshot worth showing the user is sent straight from `/tmp`.
Nothing needs to land here first.

The same applies to anything else transient: logs, dumps, scratch HTML. This directory holds role docs
and nothing else.

## Hooks

Hook configuration lives in `.claude/settings.json`; every entry has a `$comment` describing what it does.
Each script's header carries the implementation detail.

## Memory

Role-scoped and isolated via `autoMemoryDirectory` in `.claude/settings.local.json` ->
`~/.claude/memory/{{PROJECT_SLUG}}/designer/`. Do not write entries belonging to another role. Memory is not for
handoffs; handoffs are organizational knowledge and live in `../../handoffs/`.

## Handoffs

Naming: `designer-handoff-{YYYY-MM-DD}.md`, in `../../handoffs/`. The role is derived from the session cwd,
so the filename is correct automatically.

## Environment Requirements

- **CLI tools**: `jq`, `curl`, `git`
- **Environment variables**: `TRELLO_API_KEY`, and `TRELLO_API_TOKEN` or `TRELLO_TOKEN`

Hooks fail open if a tool or variable is missing: they allow the call without enforcement. Verify these are
configured before relying on the gates.
