# Start here

## What this is

This harness runs a small team of Claude Code agents on a software project. Each agent is a separate Claude
Code session with one job:

| Agent | Job | Trello column |
|---|---|---|
| Orchestrator | Plans the work and writes the cards | Next |
| Research | Documents what exists and what a card needs | Research |
| Designer | Builds the surfaces | Design |
| Dev | Writes the code | Now |
| QA | Checks the work and moves cards to Done | QA, Done |

The agents pass work along the Trello board. Hooks, small scripts that run inside Claude Code, keep each
agent in its lane. Dev cannot mark its own work done. Every agent writes notes for its next session.

You decide what gets built. When a decision is yours, an agent asks.

## How you work with it

Each agent runs in its own terminal window. You start the ones you need, in their own folders, and talk to
them there. They also reach each other directly.

You should be comfortable typing a few commands in a terminal. The orchestrator explains the rest as you go.

## What you need

- **A Mac or a Linux computer.** Windows works with changes. The orchestrator checks your computer and talks
  you through them.
- **Claude Code**, and a Claude plan that includes it.
- **A Trello account.** The board is where the agents pass work.
- **Git and GitHub**, if your project uses them. They are not required.

The orchestrator walks you through setting up each of these.

## Begin

1. Open a terminal.
2. Go to the orchestrator's folder:

   `Primary-project-name/app-or-project-name/docs/agent-workflows/orchestrator`

   On a Mac, type `cd` and a space, drag that folder from Finder into the terminal window, and press Return.
3. Type `claude` and press Return.
4. Tell the orchestrator you are setting up.

The orchestrator runs its first-start script with you. It learns what you want to build and what is on your
computer. It helps you set up Git, GitHub and Trello, then the folders, then any optional tools, then the
other agents.

You can stop at any time. When you start the orchestrator again, it picks up where you left off.

## The folders

`Primary-project-name/` is your workspace. `app-or-project-name/` is your first project. The workspace
`CLAUDE.md` explains why the folders are shaped this way and how to name new ones.
