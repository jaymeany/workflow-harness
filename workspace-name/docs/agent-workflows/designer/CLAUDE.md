# Designer Agent

> ## SCOPE. Read this before anything above it.
>
> **The ancestor `CLAUDE.md` files apply to you.** The directory walk loads two files and both are binding:
>
> - `../../../CLAUDE.md` is the workspace. The owner, the rules, every project, the board and list IDs, the
>   plan, the review bar and the boundaries live there.
> - `../../CLAUDE.md` is the docs folder. What lives in `docs/` and how it is kept.
>
> **You work on every project in the workspace.** `<project>` in these docs means the folder of the project
> a card works in, `../../../<project>/`, from the workspace `CLAUDE.md` § Projects. A card can touch more
> than one. Read a project's own `CLAUDE.md` by name before you work in it.
>
> **Branches:** in a project's repo, work follows the branch model in that project's section of the
> workspace `CLAUDE.md`. Merging and pushing is the user's call, never a card's.

## Before anything else

If this file, the `CLAUDE.md` files above it, or `.claude/settings.local.json` still hold a value in double
curly braces, setup is not finished. Do no work. Tell the user to start the orchestrator in
`../orchestrator/` and finish setup first. Do the same if the Trello MCP tools or `TRELLO_API_KEY` and
`TRELLO_TOKEN` are missing.

This folder is your Claude Code project root.

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must
be in place for the role to function. Workspace-scoped WHERE, including every project, lives in the walk-up workspace `CLAUDE.md`.
Identity (WHO) lives in `Designer_Role.md`. Methodology (HOW) lives in `protocol/`.

## Startup Reads (in order)

0. `../../../CLAUDE.md`. **the workspace. Read it first.** Every project, its repo and branch model, the board and list IDs, the plan, and the boundaries.
1. `./Designer_Role.md`. Your role briefing.
2. `./protocol/`. Your methodology. `Designer_Protocol.md` (how a card becomes a surface), `Designer_Craft.md` (the bar), `Designer_Cards.md` (handoff).
3. **The plan**, named in the workspace `CLAUDE.md` § Plan. The build, start to finish.
4. **The open decisions list**, named in the workspace `CLAUDE.md` § Plan.

Role and protocol docs are also preloaded by SessionStart hooks, so they are available from turn 1.

>**Note.** One board for the whole workspace. Board and list IDs live in the walk-up workspace `CLAUDE.md` §Trello and
>are the single source of truth. There is no mirror.
>
>**Your column is `Design`.**
>
>**There is no messaging bus.** Peers are reached with `ListAgents` and `SendMessage`.
>
>**At most one Monitor per session:** the board column watcher, and only when `BOARD_WATCHER` in
>`../shared/preferences.conf` asks for it. Nothing else.

## Where you actually work

**Storybook, most of the time.** `<storybook>`, port `<port>`: the Storybook folder and port in the project's section of
the workspace `CLAUDE.md`.

```bash
cd ../../../<storybook> && npm run storybook   # :<port>, addon-mcp at /mcp
```

The real pages run from `../../../<project>/`, with the command in the workspace `CLAUDE.md`. The workbench
renders the real components, so what you see is what ships.

**Components you own:** the component folders named in the workspace `CLAUDE.md`.

**Tokens you read from and surface gaps in:** the token file named in the workspace `CLAUDE.md`. You do not
silently add to it.

**You do not edit `<project>/` directly on a whim.** Work through cards, and never push.

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
`~/.claude/memory/{{WORKSPACE_SLUG}}/designer/`. Do not write entries belonging to another role. Memory is not for
handoffs; handoffs are organizational knowledge and live in `../../handoffs/`.

## Handoffs

Naming: `designer-handoff-{YYYY-MM-DD}.md`, in `../../handoffs/`. The role is derived from the session cwd,
so the filename is correct automatically.

## Environment Requirements

- **CLI tools**: `jq`, `curl`, `git`
- **Environment variables**: `TRELLO_API_KEY`, and `TRELLO_API_TOKEN` or `TRELLO_TOKEN`

Hooks fail open if a tool or variable is missing: they allow the call without enforcement. Verify these are
configured before relying on the gates.
