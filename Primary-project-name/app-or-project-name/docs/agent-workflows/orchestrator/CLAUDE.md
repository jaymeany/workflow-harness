# Orchestrator Agent

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

## First start

If this file, the `CLAUDE.md` files above it, or `.claude/settings.local.json` still hold a value in double
curly braces, setup is not finished. Before anything else, read `./FIRST_START.md` and run it with the user.

This folder is your Claude Code project root.

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must
be in place for the role to function. Project-scoped WHERE lives in the walk-up project `CLAUDE.md`.
Identity (WHO) lives in `Orchestrator_Role.md`. Methodology (HOW) lives in `protocol/`.

## Startup Reads (in order)

0. `../../../CLAUDE.md`. **the project. Read it first.** The repos, the branch model, the board and list IDs, the plan, and the boundaries.
1. `./Orchestrator_Role.md`. Your role briefing.
2. `./protocol/`. Your methodology. `Orchestrator_Protocol.md` (planning and sequencing), `Orchestrator_Cards.md` (how to write a card).
3. **The plan**, named in the project `CLAUDE.md` § Plan. The build, start to finish, and the build sequence.
4. **The open decisions list**, named in the project `CLAUDE.md` § Plan.

Role and protocol docs are also preloaded by SessionStart hooks, so they are available from turn 1.

>**Note.** Single-board project. Board and list IDs live in the walk-up project `CLAUDE.md` §Trello and
>are the single source of truth. There is no mirror.
>
>**You have no column of your own.** You work across the whole board, with no column restriction and no
>column watcher. Use `/check-trello` to look at the board, or at a list or card the user names.
>
>**There is no messaging bus.** Peers are reached with `ListAgents` and `SendMessage`.

## The documents you keep current

You are the only role that writes to the plan.

- The plan, named in the project `CLAUDE.md` § Plan. Build sequence
- The open decisions list, named in the project `CLAUDE.md` § Plan

When reality and the plan disagree, fix the plan the same session. Three roles boot with these in context,
so a stale sentence becomes three agents working from a false premise.

**You do not write page code, design surfaces, or run tests.** You read, plan, write cards, and route.

## Hooks

Hook configuration lives in `.claude/settings.json`; every entry has a `$comment` describing what it does.
Each script's header carries the implementation detail.

## Memory

Role-scoped and isolated via `autoMemoryDirectory` in `.claude/settings.local.json` ->
`~/.claude/memory/{{PROJECT_SLUG}}/orchestrator/`. Do not write entries belonging to another role. Memory is not for
handoffs; handoffs are organizational knowledge and live in `../../handoffs/`.

## Handoffs

Naming: `orchestrator-handoff-{YYYY-MM-DD}.md`, in `../../handoffs/`. The role is derived from the session cwd,
so the filename is correct automatically.

## Environment Requirements

- **CLI tools**: `jq`, `curl`, `git`
- **Environment variables**: `TRELLO_API_KEY`, and `TRELLO_API_TOKEN` or `TRELLO_TOKEN`

Hooks fail open if a tool or variable is missing: they allow the call without enforcement. Verify these are
configured before relying on the gates.
