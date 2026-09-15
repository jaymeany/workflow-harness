# Research Agent

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

If this file, the `CLAUDE.md` files above it, `.claude/settings.local.json` or
`.claude/hooks/protocol-enforcement.conf` still hold a value in double curly braces, setup is not finished.
Do no work. Tell the user to start the orchestrator in `../orchestrator/` and finish setup first. Do the same
if the Trello MCP tools or `TRELLO_API_KEY` and `TRELLO_TOKEN` are missing.

This folder is your Claude Code project root.

This file answers role-scoped **WHERE**: where role files live, where memory writes, what environment must be in place for the role to function. Project-scoped WHERE lives upstream in the walk-up `CLAUDE.md` files, which the directory walk has loaded into your context. Identity (WHO) lives in `Research_Role.md`. Methodology (HOW) lives in `protocol/` (split across `Research_Protocol.md`, `Research_Cards.md`, `Research_Coordination.md`).

## What's in this directory

This directory holds the Research role's configuration. Hooks in `./.claude/hooks/` enforce role-scoped rules at write-time and move-time.

The pieces:

- `./Research_Role.md` — role identity, disposition, hard constraints. Loaded into `additionalContext` by `load-research-role.sh` at session start.
- `./protocol/Research_Protocol.md` — research methodology (tool selection, quality checks, judgment calls, pattern-recognition cues). Loaded by `load-research-protocol.sh`.
- `./protocol/Research_Cards.md` — card mechanics (description, sizing, naming, handoff). Loaded by `load-research-cards.sh`.
- `./protocol/Research_Hooks.md` — the hook-enforced inventory (what fires, on what, and each hook's built-in escape). Loaded by `load-research-hooks.sh`. Split out of `Research_Cards.md` when that doc crossed the context cap.
- `./protocol/Research_Coordination.md` — talking to Dev and QA via ListAgents/SendMessage, and what belongs on the board instead. Loaded by `load-research-coordination.sh`.

One SessionStart hook loads *state* rather than docs: `load-research-trello-catchup.sh` (column reminder plus the watcher arm block). It is excluded from the digest below — its output varies with board state, so a size WARN on it would be meaningless. `load-agent-comms.sh` emits static text about reaching peers.

The protocol is split across four files along semantic seams (methodology / card mechanics / hook inventory / coordination), one loader per file. Claude Code's `additionalContext` payload caps around ~10K chars per hook; over-cap content gets persisted to disk and substituted with a small preview, so each file stays under the cap by construction. `load-status-digest.sh` runs last in `SessionStart` and prints an OK/WARN line confirming every loader inlined in full — if a file ever crosses the cap the digest surfaces it; the fix is a further semantic split, never byte-range slicing inside a loader.

If you need to re-read any of the above mid-session, use `Read` directly.

>**Note.** Single-board project. Board and list IDs live in the walk-up project `CLAUDE.md` §Trello, the single source of truth, no mirror.
>
>**There is no messaging bus.** Peers are reached with `ListAgents` and `SendMessage`. See `load-agent-comms.sh`.
>
>**Arm exactly one Monitor per session:** the board column watcher.

## Handoffs

Handoffs are the artifact Research writes routinely. Naming convention: `research-handoff-{YYYY-MM-DD}.md`, dropped in the `../../handoffs/` directory. Capture session state for cross-session continuity: what was done, what's left, current board state.

## Memory

Your memory is role-scoped and isolated to this instance via the `autoMemoryDirectory` pointer in `.claude/settings.local.json` → `~/.claude/memory/{{PROJECT_SLUG}}/research/`. Do not write entries that belong to Dev or QA. Memory is not for handoffs — handoffs are organizational knowledge and live in `../../handoffs/`.

## Environment Requirements

For the hooks in `./.claude/hooks/` to function, the runtime must have:

- **CLI tools**: `jq`, `curl`
- **Environment variables**:
  - `TRELLO_API_KEY`
  - `TRELLO_API_TOKEN` (or `TRELLO_TOKEN`)

`gate-research-complete.sh` (which enforces the `## Research Complete` marker before cards move to "Now") **fails open** if any of these are missing — it allows the move without enforcement. Verify these are configured before relying on the gate.
