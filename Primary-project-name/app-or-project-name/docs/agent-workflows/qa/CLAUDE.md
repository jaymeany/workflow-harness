# QA Agent

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

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must be in place for the role to function. Project-scoped WHERE lives upstream in the walk-up `CLAUDE.md` files, which the directory walk has loaded into your context. Identity (WHO) lives in `QA_Role.md`. Methodology (HOW) lives in `protocol/` (split across `QA_Checks.md`, `QA_Surface.md`, `QA_Decisions.md`, `QA_Workflow.md`, `QA_Coordination.md`).

## What's in this directory

This directory holds the QA role's configuration. Hooks in `./.claude/hooks/` enforce role-scoped rules at write-time and move-time.

The pieces:

- `./QA_Role.md` — role identity, disposition, column, card mechanics, tags. Loaded into `additionalContext` by `load-qa-role.sh` at session start.
- `./protocol/QA_Checks.md` — the gate and the checks about whether a claim is true (0, 0b, 1-3). Loaded by `load-qa-checks.sh`.
- `./protocol/QA_Surface.md` — the checks about whether the rendered page holds up (5-7). Loaded by `load-qa-surface.sh`. Split out of `QA_Checks.md` when it neared the context cap.
- `./protocol/QA_Decisions.md` — decision matrix (PASS / FAIL / BOUNCE) and §9 comment template. Loaded by `load-qa-decisions.sh`.
- `./protocol/QA_Hooks.md` — the hook-enforced constraints. Loaded by `load-qa-hooks.sh`. Split out of `QA_Role.md` when that doc crossed the context cap.
- `./protocol/QA_Workflow.md` — testing, iteration, hotfix, E2E, what NOT to flag, documentation outputs. Loaded by `load-qa-workflow.sh`.
- `./protocol/QA_Coordination.md` — card naming convention. Loaded by `load-qa-coordination.sh`.

The protocol is split across six files along semantic seams (truth checks / surface checks / decisions / hook constraints / workflow / coordination), one loader per file. Claude Code's `additionalContext` payload caps around ~10K chars per hook; over-cap content gets persisted to disk and substituted with a small preview, so each file stays under the cap by construction. `load-status-digest.sh` runs last in `SessionStart` and prints an OK/WARN line confirming every loader inlined in full — if a file ever crosses the cap the digest surfaces it; the fix is a further semantic split, never byte-range slicing inside a loader.

If you need to re-read any of the above mid-session, use `Read` directly.

>**Note.** Single-board project. Board and list IDs live in the walk-up project `CLAUDE.md` §Trello, the single source of truth, no mirror.
>
>**There is no messaging bus.** Peers are reached with `ListAgents` and `SendMessage`. See `load-agent-comms.sh`.
>
>**Arm exactly one Monitor per session:** the Trello column watcher.
>
>**Severity axis.** Whether the claim is true and whether it should be public, not whether it would survive load. The walk-up project `CLAUDE.md` carries the boundaries; read them rather than assuming. See `QA_Role.md` §Disposition.

## Hooks (installed in `./.claude/hooks/`)

Hook configuration lives in `.claude/settings.json` — every entry has a `$comment` field describing what it does. Each script's header has the full implementation detail.

## Memory

Your memory is role-scoped and isolated to this instance via the `autoMemoryDirectory` pointer in `.claude/settings.local.json` → `~/.claude/memory/{{PROJECT_SLUG}}/qa/`. Don't write entries about work outside QA's lane. Memory is not for handoffs — handoffs are organizational knowledge and live in `../../handoffs/`.

## Environment Requirements

For the hooks in `./.claude/hooks/` to function, the runtime must have:

- **CLI tools**: `jq`, `curl`
- **Environment variables**:
  - `TRELLO_API_KEY`
  - `TRELLO_API_TOKEN` (or `TRELLO_TOKEN`)

Hooks fail open if their required tools or env vars are missing — they allow the tool call without enforcement. Verify these are configured before relying on the gates.

## Handoffs

Naming convention: `qa-handoff-{YYYY-MM-DD}.md`, dropped in the `../../handoffs/` directory.
