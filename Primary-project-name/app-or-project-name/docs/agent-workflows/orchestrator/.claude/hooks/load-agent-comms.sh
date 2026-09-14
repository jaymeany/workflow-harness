#!/bin/bash
#
# load-agent-comms.sh — Claude Code SessionStart hook
#
# States how peers are reached: directly, with ListAgents and SendMessage.
# There are no queues and nothing to poll.
#
# Exit codes: always 0 — informational only.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

ctx="TALKING TO THE OTHER ROLES

Research, Dev and QA each run as their own Claude Code session on this
machine. They reach each other directly:

- \`ListAgents\` — who is running right now
- \`SendMessage({to: \"<name>\", message: \"...\"})\` — send to a named peer

There are no message queues and nothing to poll. Peers are reached directly.
path and do not look for one. If a peer is not listed by ListAgents it is not
running, and the work still routes through the board.

THE ORCHESTRATOR HAS NO COLUMN AND ARMS NO MONITOR. Use /check-trello to look
at the board, or at a list or card the user names.

WHAT STILL GOES THROUGH THE BOARD, NOT THROUGH A MESSAGE

A message is for a question. The board is for state. Anything that changes
what work exists or where it stands is a card operation, and a peer message
never substitutes for one:

- moving a card between columns
- the Implementation Notes handoff comment
- a FAIL, a BOUNCE, or a PASS
- raising new work

Say it on the board first. Message a peer only when you need an answer that
the card cannot carry, or to tell them something landed that they are waiting
on."

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
