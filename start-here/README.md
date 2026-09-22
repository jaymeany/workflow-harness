# Start here

## What this is

This harness runs a small team of Claude Code agents on a software project. Each agent is a separate Claude
Code session with one job:

| Agent | Job | Trello column |
|---|---|---|
| Orchestrator | Plans the work and writes the cards | None. It works across the board |
| Research | Documents what exists and what a card needs | Research |
| Designer | Builds the surfaces | Design |
| Dev | Writes the code | Now |
| QA | Checks the work, then moves a card to Done or sends it back | QA |

The agents pass work along the Trello board. Hooks, small scripts that run inside Claude Code, keep each
agent in its lane. Dev hands finished work to QA, and QA decides when it's done. Every agent writes notes for
its next session.

You decide what gets built. When a decision is yours, an agent asks.

## How you work with it

Each agent runs in its own terminal window. You start the ones you need, in their own folders, and talk to
them there. They also reach each other directly.

You should be comfortable working in a terminal app. The board and Storybook have their own screens, but
the work and the configuration happen in the terminal. The orchestrator explains the rest as you go.

## What you need

- **A Mac or a Linux computer.** Windows works with changes. The orchestrator checks your computer and talks
  you through them.
- **Claude Code**, and a Claude plan that includes it.
- **A kanban board.** The board is where the agents pass work. Trello is the one that ships, so you need a
  Trello account.
- **Git and GitHub**, if your project uses them. They are not required.

The orchestrator walks you through setting up each of these.

## Begin

If you used the install script, the orchestrator is already running and the folders are already named.
Skip to it and answer its questions. The rest of this section is for a fork or a ZIP download.

1. Open a terminal.
2. Go to the orchestrator's folder:

   `Primary-project-name/app-or-project-name/docs/agent-workflows/orchestrator`

   On a Mac, type `cd` and a space, drag that folder from Finder into the terminal window, and press Return.
3. Type `claude` and press Return.
4. Tell the orchestrator you are setting up. Something like:

   `I am setting up. Run first start with me.`

   Anything works. It checks for itself whether setup has been done, and says so before it does
   anything else.

The orchestrator runs its first-start script with you. It learns what you want to build and what is on your
computer. It helps you set up Git, GitHub and Trello, then the folders, then any optional tools, then the
other agents.

You can stop at any time. When you start the orchestrator again, it picks up where you left off.

## Changing things later

The orchestrator is also how you change the setup after it is done. A different Trello board, a tool you
skipped the first time, a different branch model, a renamed folder.

Start it and say what you want in your own words. There is no command to remember and no file to find.

You also don't have to remember what you skipped. Ask it what is not set up. It will tell you what is
unset, what each one affects, and which ones are optional, and then you decide. Leaving something unset on
purpose is fine. Several parts of the harness are optional.

## The folders

`Primary-project-name/` is your workspace. `app-or-project-name/` is your first project. The workspace
`CLAUDE.md` explains why the folders are shaped this way and how to name new ones.
