# Dev Agent

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

If this file, the `CLAUDE.md` files above it, `.claude/settings.local.json` or
`.claude/hooks/gate-per-card-commit.sh` still hold a value in double curly braces, setup is not finished. Do
no work. Tell the user to start the orchestrator in `../orchestrator/` and finish setup first. Do the same if
the Trello MCP tools or `TRELLO_API_KEY` and `TRELLO_TOKEN` are missing.

This folder is your Claude Code project root.

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must be in place for the role to function. Workspace-scoped WHERE, including every project, lives in the walk-up workspace `CLAUDE.md`. See the scope note above for the other two files that bind you. Identity (WHO) lives in `Dev_Role.md`. Methodology (HOW) lives in `protocol/` (`Dev_Protocol.md`, `Dev_Standards.md`, `Dev_Cards.md`, `Dev_Build.md`).

## Startup Reads (in order)

0. `../../../CLAUDE.md` — **the workspace. Read it first.** Every project, its repo and branch model, the board and list IDs, the plan, and the boundaries.
0b. `../../../<project>/CLAUDE.md` — **the code**, for each project the card touches. Off the walk-up, so read it explicitly, if the project has one.
1. `./Dev_Role.md` — your role briefing (column ownership, tools, decision protocol)
2. `./protocol/Dev_Protocol.md` — your methodology
3. **The plan**, named in the workspace `CLAUDE.md` § Plan — **the build, start to finish.** Every card you will pick up is a step in it. Read it before your first card so you know where your card sits in the whole.

Protocol and role docs are also preloaded into session context by SessionStart hooks (see below), so they're available from turn 1.

>**Note.** One board for the whole workspace. Board and list IDs live in the walk-up workspace `CLAUDE.md` §Trello and are the single source of truth. There is no mirror.
>
>**There is no messaging bus.** Peers are reached directly: `ListAgents` to see who is running, `SendMessage` to talk to them. See `load-agent-comms.sh`.
>
>**At most one Monitor per session:** the board column watcher, from `../shared/arm-column-watcher.sh`, and only when `BOARD_WATCHER` in `../shared/preferences.conf` asks for it. Nothing else, ever.

## Hooks (installed in `./.claude/hooks/`)

Hook configuration lives in `.claude/settings.json` — every entry has a `$comment` field describing what it does. Each script's header has the full implementation detail.

## Memory

Your memory is role-scoped and isolated to this instance via the `autoMemoryDirectory` pointer in `.claude/settings.local.json` → `~/.claude/memory/{{WORKSPACE_SLUG}}/dev/`. Memory is for cross-session preferences and corrections about Dev's work — don't write entries about work outside Dev's column. Memory is not for handoffs.

## Environment Requirements

For the hooks in `./.claude/hooks/` to function, the runtime must have:

- **CLI tools**: `jq`, `curl`, `sed`
- **Environment variables**:
  - `TRELLO_API_KEY`
  - `TRELLO_API_TOKEN` (or `TRELLO_TOKEN`)

Hooks fail open if their required tools or env vars are missing — they allow the tool call without enforcement. Verify these are configured before relying on the gates.

## Handoffs

Handoffs are the only artifact Dev writes routinely. Naming convention: `dev-handoff-{YYYY-MM-DD}.md`, dropped in the `../../handoffs/` directory.

## References

- `Dev_Role.md` — role identity, voice, disposition, hard constraints
- `protocol/Dev_Protocol.md` — implementation methodology (HOW)
