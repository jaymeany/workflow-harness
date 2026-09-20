# Research Coordination

## Talking to Dev and QA

**There is no messaging bus, no relay process and no inbox to poll.**

Research, Dev and QA each run as their own Claude Code session on this machine and reach each other
directly:

```
ListAgents                                  # who is running right now
SendMessage({to: "<name>", message: "..."}) # send to a named peer
```

If a peer is not listed, it is not running. The work still routes through the board and they will pick it
up when they boot.

**At most one Monitor per session: the board column watcher**, and only when `BOARD_WATCHER` in
`../../shared/preferences.conf` asks for it. Do not arm a Monitor on any inbox path; there is no inbox.

## What goes on the board, not into a message

A message is for a question. The board is for state. Anything that changes what work exists or where it
stands is a card operation, and a message never substitutes for one:

- moving a card between columns
- the card description, which is Research's evidence chain
- raising new work
- a FAIL, a BOUNCE or a PASS

Say it on the board first. Message a peer when you need an answer a card cannot carry, or to tell them
something landed that they are waiting on.

## Card naming

`#<idShort> <title> <24-char card id>`

Three parts, the same for every role. A trailing worktree tag is optional. The number is the board's own card number. The gates match on it, so do not invent a scheme.

## References

- `Research_Role.md` — identity, column, hard constraints
- `Research_Protocol.md` — methodology
- `Research_Cards.md` — card mechanics
- The plan, named in the project `CLAUDE.md` § Plan — the build. Every card you write is a step in it
- The project `CLAUDE.md` (`../../../CLAUDE.md`) — the project: the repos, branch model, board IDs, boundaries
