# First start

You are the orchestrator, and this is the configuration script for the harness. Run it in order. Stop at
any step the user wants to pause on. When you start again, check which placeholders are still unfilled and
pick up from the first step that is not done.

The goal is simple. When this script is finished, the user can use the harness, and every agent in it has
what it needs.

## This file is not only for the first run

It is the one place the harness is configured, and the user comes back to it whenever something changes.
The name says first start because that is when it is usually run, not because it runs once.

Reach for this file, at whichever step covers the question, whenever the user wants to:

- use a different board, or different columns
- add a tool they skipped, such as Storybook, Axon or Playwright
- change the branch model, the review bar, the boundaries or the commands
- rename a folder, add a project, or point at a different code repo
- record a test suite or a service registry the project did not have before
- find out what they never configured in the first place

**The user does not have to remember what they skipped, and does not have to name this file.** Anything
like "what did I not set up", "can I change the board", "I want to add Storybook now" or "is this
configured properly" is this script. Find what is unfilled, tell them what it affects, and let them decide
whether it matters. Several values are optional on purpose.

Nothing here blocks them. A value they choose to leave unset is a decision, not a fault. Say what it costs
and move on.

Re-running a step is safe. Confirm what is already recorded before you change it, and do not overwrite an
answer the user did not ask you to change.

## How to run it

- **The user has used a terminal a little.** Explain each step in plain words. Give one step at a time, say
  what they should see, and wait for them to confirm.
- **Offer to walk them through each setup task.** When they want help, look up the current steps on the
  web before you give them. Tools change their setup screens.
- **Check what you can check yourself.** Run the command rather than asking the user.
- **Secrets never go in this chat.** API keys and tokens go in the user's shell profile, typed by them.
  Check that a variable is set with `[ -n "$NAME" ] && echo set || echo missing`. Never print a key or token.
- **Write each answer into its file as you get it,** so a restart loses nothing.
- **Some steps need a restart** of Claude Code, because it reads environment variables and MCP servers when
  it starts. Say so, and tell the user what to type when they come back.
- **Preferences are the user's.** Where this script offers a default, it is a suggestion. Record what the
  user chooses.

## Open the session before you run a step

The user has just started an agent and does not know what is coming. Say what this is before you ask the
first question. Cover six things in your own words:

- What they are setting up is a software factory. Five agents, each with its own rules, memory and checks.
- There are a lot of moving parts, and most get settled once. The work is front-loaded on purpose.
- It is multi-step. Some of it every project needs. The rest depends on how the user works.
- It will take a while. Give the range.
- Nothing is locked in. Any of it can be changed later by asking you or any other agent.
- They can stop at any point, and you pick up where you left off. You will keep a task list.

Something like:

> This is a multi-step setup, and it will take a bit. Probably 30 to 45 minutes, depending on how much we
> do. What you're setting up is a software factory: five agents, each with its own rules, memory and
> checks. There are a lot of moving parts, and you settle most of them once. The more we do now, the less
> you have to explain later.
>
> Some of it every project needs. The rest depends on how you like to work. Nothing is locked in. Ask me,
> or any of the other agents, and we can change any of it. You can stop at any point and we pick up where
> we left off. I'll keep a task list so you can see where we are.

**Tone.** Say the size plainly, without apology and without warning them off. It is a lot because it is a
factory, not because it is badly built. Front-loaded is the honest frame: settle it now and it stays
settled. Do not undersell it either. A user told this is quick, who finds out at step 3 that it is not,
trusts you less than one who was told the truth at step 1.

Then give the scale. Seven steps. Three the harness cannot run without: the environment check, Trello, and
the folder names and stack. Git, the optional tools and the other agents depend on the project.

Trello ends in a restart of Claude Code, because Claude Code reads environment variables and MCP servers
when it starts. So does the finish, so every agent boots with the filled-in files. Installing an optional
MCP tool in step 5 needs one too.

**About the range.** It is a feel for the size, not a promise. There is no way to be accurate about it.
What drives the time is how much the user wants explained and how many of the optional steps they take.
Say it once, say it depends, and move on. Do not revise it mid-setup, and do not apologise for it if
setup runs long.

## The task list

Build it with `TodoWrite` at the start of every setup session, not only the first. Show it before the first
question, so the user sees the shape of the thing before they answer anything.

**The state is already on disk. Do not keep a separate progress file.** A step is done when the values it
writes are filled in. Read them and derive the list:

| Step | Done when |
|---|---|
| 1. Intentions and environment | `{{WORKSPACE_NAME}}`, `{{WORKSPACE_PURPOSE}}`, `{{WORKSPACE_RULES}}`, `{{OWNER_NAME}}`, `{{OWNER_ROLE}}`, `{{PROJECT_NAME}}`, `{{PROJECT_SUMMARY}}` are filled |
| 2. Git and GitHub | `{{CODE_REMOTE}}`, `{{DOCS_REMOTE}}`, `{{DOCS_GIT}}`, `{{WORK_BRANCH}}`, `{{PUBLISH_BRANCH}}`, `{{BRANCH_MODEL}}`, `{{PUBLISH_EFFECT}}` are filled. `none` is a real answer |
| 3. Trello | `{{BOARD_ID}}` in `board/board.conf`, plus `{{TRELLO_BOARD_ID}}`, `{{TRELLO_BOARD_NAME}}` and the six `{{LIST_ID_*}}`. Also `TRELLO_API_KEY` set in the shell and the `mcp__trello__*` tools present |
| 4. Folders, names and stack | `{{CODE_DIR}}`, `{{STACK}}`, `{{COMMANDS}}`, `{{COMPONENT_FOLDERS}}`, `{{COMPONENT_LIBRARY}}`, `{{TOKEN_FILE}}` |
| 5. Optional tools | `{{TOOLS}}`, `{{TEST_SUITE}}`, `{{SERVICE_REGISTRY}}`, and the four `{{STORYBOOK_*}}` if Storybook is in use |
| 6. The other agents | `{{PROJECT_SLUG}}` filled, each chosen agent's `.claude/settings.local.json` holding its `autoMemoryDirectory`, and `BOARD_WATCHER` answered in `shared/preferences.conf` |
| 7. Plan and boundaries | `{{PLAN_FILE}}`, `{{DECISIONS_FILE}}`, `{{REVIEW_BAR}}`, `{{BOUNDARIES}}` |

Step 7 lists exactly where to search for unfilled values. Use those paths and nowhere else.

How to mark them:

- **In progress** when you start asking a step's questions. **Done** when its values are written to their
  files, not when the user answers out loud.
- **Skipped is finished.** A user who declines Storybook has completed step 5. Mark it done and say it was
  skipped. Leaving it open reads as work outstanding when it is a decision already made.
- **Never mark a step done from memory of an earlier session.** Read the files. After a restart, rebuild
  the whole list from what is on disk.

The list is also the answer to "what did I not set up". Rebuild it and show it.

## 1. Intentions and environment

Ask what the user wants to build and why. Record it in the project `CLAUDE.md` under What this is.

Check the computer:

```bash
uname -s
claude --version
git --version
jq --version
curl --version
command -v pgrep
```

- `Darwin` is a Mac and `Linux` is Linux. The hooks are bash scripts and work on both.
- **On Windows**, name the changes before going further. The hooks need a bash shell. Per Claude Code's
  docs, hooks run in Git Bash when Git for Windows is installed, and in PowerShell when it is not. The
  simplest path is to run Claude Code inside WSL, where everything works as on Linux. Talk the user through
  the path they choose.
- `jq`, `curl` and `pgrep` are required by the hooks. A hook that is missing a tool allows everything
  without checking, so install anything missing before going on.
- The agents reach each other with `ListAgents` and `SendMessage`. These need Claude Code 2.1.224 or later.
  If the version is older, the user runs `claude update`.

## 2. Git and GitHub

Git and GitHub are used if the project has them. They are not required.

Ask whether the project's code is, or will be, in a git repository, and whether it is on GitHub. If yes and
the user needs help, walk them through installing git, creating a GitHub account, and signing in with the
GitHub command line tool `gh`. If the code already exists on GitHub, help them clone it into the project
folder, under the name they choose in step 4.

Record each repo's remote in the project `CLAUDE.md` under Repos and branches. Write `none` for a repo with
no remote. Record how the docs folder is tracked in the docs `CLAUDE.md` under Git. The docs repo works on
`main`.

**The branch model for the code is the user's choice.** Ask how they want to work. Two common models:

- Work on a `dev` branch, merge to `staging`, then push from `staging` to `main`.
- Work on a `dev` branch, then merge to `main`.

Record the work branch, the publishing branch, and the model in the project `CLAUDE.md`. If the work branch
does not exist yet, help the user create it.

## 3. Trello

Trello is required. The agents pass work along a Trello board.

1. **An account.** Help the user sign up at trello.com if they do not have one.
2. **An API key and token.** Look up Trello's current steps on the web, then walk the user through them.
   Trello issues the key from its app admin page, and the token from a link next to the key. Tell the user
   before they create them: the key and token act as the user, and can reach every board their Trello
   account can reach.
3. **The shell profile.** The user adds the key and token to their shell profile, for example `~/.zshrc`
   on a Mac:

   ```bash
   export TRELLO_API_KEY=...
   export TRELLO_TOKEN=...
   ```

   The Trello MCP server reads `TRELLO_TOKEN`. The hooks accept `TRELLO_TOKEN` or `TRELLO_API_TOKEN`.
4. **The Trello MCP server.** It does not ship with this harness. The user installs
   [`@delorenj/mcp-server-trello`](https://github.com/delorenj/mcp-server-trello) by following its README.
   Register it under the name `trello`, at user scope, so every agent folder can use it. The hooks match
   tool names that begin `mcp__trello__`, so any other name turns the gates off without an error.
5. **Restart.** The user quits Claude Code, opens a new terminal, starts the orchestrator again, and says
   they are continuing setup. Confirm the `mcp__trello__*` tools are present. Do not list every board on the
   account to test the connection; on an account with many boards the response is very large.
6. **The API Developer ID Helper Power-Up**, by Sensum365. Help the user add it to their board. It shows the
   board's ID, each card's API ID, and other board information, which the card names and the project
   `CLAUDE.md` use.
7. **The board.** Ask the user which board to use, by name: an existing board, or a new one they create in
   Trello. If they have more than one board, ask; do not guess. Get the board's ID from the Power-Up, then
   tell the user the board name and ID you will use before you make any other Trello call. Suggest these
   column names, in this order: `Next`, `Research`, `Design`, `Now`, `QA`, `Done`. The user can choose other
   names, as long as each role's column keeps its word: `research`, `design`, `now`, `qa`, `done`. The hooks
   find columns by those words. The orchestrator has no column.
8. **Labels.** The hooks match labels by color: green for Research complete, blue for Needs research, red
   for a QA FAIL, purple for QA complete, orange for a QA tracking card. The hooks create a missing label
   when they need it.
9. **Record** the board name, board ID and list IDs in the project `CLAUDE.md` under Trello.

## 4. Folder shape, names and stack

Explain the folders, using the workspace `CLAUDE.md` section Why the folders are shaped this way. The
structure stays, but the user can rename `Primary-project-name/` and `app-or-project-name/`, and add
projects or folders. No hook uses those two names. If the user renames a folder that holds this session,
they rename it while Claude Code is closed, then start the orchestrator again from the new path.

Then agree with the user:

- **The code folder name.** It sits inside the project folder. Use the repository's name, in lowercase with
  hyphens.
- **The stack.** What the project is built with.
- **The commands** to run, build, test and check the project.
- **Where the plan and the open decisions list live,** and what they are called. The user decides.
- **The token file, component folders and component library,** if the project has them. Write `none` for
  any it does not have.
- **The review bar:** what done looks like for a change.
- **The boundaries:** what must never appear in the product.
- **What a push to the publishing branch does,** for example a deploy, or nothing.

Fill the workspace `CLAUDE.md`, the project `CLAUDE.md` and the docs `CLAUDE.md` with these answers.

## 5. Optional tools

For each tool, explain what it is for, give the link to its repo, and say whether it fits this project.
Fetch and set up a tool only if it fits and the user wants it. Record the tools in use in the project
`CLAUDE.md` under Tools.

| Tool | What it is for | Used by | Link |
|---|---|---|---|
| Storybook, with its MCP addon | A workbench where the Designer builds surfaces before Dev builds them in | Designer | [storybook.js.org](https://storybook.js.org) |
| Axon | A code intelligence engine. It indexes the codebase into a graph agents can query | Research | [github.com/harshkedia177/axon](https://github.com/harshkedia177/axon) |
| Playwright MCP | Opens the product in a real browser for screenshots and checks | Designer, QA | [github.com/microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) |

- **Axon.** In at least one project its MCP proxy returned empty results while its command line tool worked,
  so test both and use what answers.
- **Playwright.** When two roles use Playwright at the same time, each needs its own browser profile. The
  Playwright MCP README covers this.
- **A test suite** is optional. If the project has one, QA writes and maintains it. Record it in the project
  `CLAUDE.md` under Test suite.
- **A service registry** is optional. If the project has one, QA maintains it. Record it under Service
  registry.
- **A message relay or bus**, such as Telegram, is not part of this harness. The agents already reach each
  other with `ListAgents` and `SendMessage`. A user who wants a relay builds it with Claude.

**If the project has no Storybook,** the role docs and hooks still mention it. Ask the user whether to
remove those references or leave them, and do what they choose. The references are in
`dev/.claude/hooks/gate-per-card-commit.sh`, the push message in the orchestrator's and designer's
`block-destructive-bash.sh`, the designer's docs, and `dev/protocol/Dev_Build.md`.

## 6. The other agents

1. Agree with the user which agents to spin up. They can start any of them later.
2. Choose a project slug: the project name in lowercase with hyphens. It keeps each agent's memory and
   Trello watcher separate from other projects on the same computer.
3. In each agent folder, write the memory location into `.claude/settings.local.json`, using the slug and
   the agent's folder name:

   ```json
   {"autoMemoryDirectory": "~/.claude/memory/<slug>/<agent>"}
   ```

   The file ships empty on purpose. Until this step, each agent uses Claude Code's default memory location.
4. Explain the flow and who does what:
   - **Orchestrator:** the plan. Works across the whole board with no column of its own.
   - **Designer:** the surfaces, and the Storybook server if the project uses one. Hands a finished card to
     Research, or messages Research, depending on the context.
   - **Research:** what exists and what a card needs. Writes the card for Dev and moves it to Now. Only
     Research moves a card to Now.
   - **Dev:** the code, and GitHub for the code, under the commit and push rules. Moves finished cards to QA.
   - **QA:** checks the work. Moves a card to Done, or bounces it to Dev, Research or Design depending on the
     gap. Manages the docs repo, the service registry if there is one, and the test suite if there is one.

   Work starts in Research or Design.
5. Explain how to start an agent: open a new terminal window, `cd` into its folder under
   `docs/agent-workflows/`, and type `claude`. Give the full path for each.

6. **Ask about the column watcher.** Each agent with a column can watch it and wake when a card arrives,
   instead of waiting to be asked. Put it to the user plainly and record their answer in
   `docs/agent-workflows/shared/preferences.conf` as `BOARD_WATCHER`:

   - **`auto`**: every role with a column arms its watcher on its first turn. Work moves between roles on
     its own. Best when several roles run at once and you are not watching them.
   - **`ask`**: each role offers the watcher at session start and waits. Best when you want it on some
     sessions and not others.
   - **`off`**: no watcher anywhere. You read the column with `/check-trello` when you want to. Best when
     you drive one role at a time. **This is the default**, so doing nothing is a real answer.

   Say what it costs: a watcher is about 3000 characters of context per role at session start plus one
   background poll each, and it is a read-only poll every 20 seconds. Say what off costs: a card handed to
   a role does not wake it, so someone has to look.

   This is changeable any time. Nothing is locked in.
7. Explain the `CLAUDE.md` files in the walk-up: each agent loads the workspace file, the project file, the
   docs file and its own, from its folder up.

## 7. Fill the placeholders

Search for `{{` in these places and fill every value:

- `Primary-project-name/CLAUDE.md`
- `app-or-project-name/CLAUDE.md`
- `app-or-project-name/docs/CLAUDE.md`
- every `CLAUDE.md`, `.md` doc and `.claude/hooks/` file under `docs/agent-workflows/`
- `docs/agent-workflows/shared/`. The hooks every role runs from one copy. Not inside any
  `.claude/hooks/` folder, so a search that only looks there will miss it.
- `docs/agent-workflows/board/board.conf`. The hooks read the board id from
  here. Leave it unfilled and every board gate quietly allows everything.

**Search those places and nowhere else. Never the code folder or the Storybook folder.** Handlebars, Jinja,
Vue, Angular and Go templates all write `{{ }}`, so a project's own source will match and the hits are
meaningless. Searching the harness's own files cannot pick wrong.

This file, `FIRST_START.md`, keeps its placeholders. It is the script, not configuration.

| Placeholder | Value |
|---|---|
| `{{WORKSPACE_NAME}}`, `{{WORKSPACE_PURPOSE}}` | What the user calls the workspace, and what it is for |
| `{{OWNER_NAME}}`, `{{OWNER_ROLE}}` | What the agents call the user, and the user's role |
| `{{WORKSPACE_RULES}}` | Anything no agent may do anywhere in the workspace, or `None.` |
| `{{PROJECT_NAME}}`, `{{PROJECT_SUMMARY}}`, `{{STACK}}` | The project, what it is, and what it is built with |
| `{{PROJECT_SLUG}}` | The slug from step 6 |
| `{{CODE_DIR}}` | The code folder name from step 4 |
| `{{WORK_BRANCH}}`, `{{PUBLISH_BRANCH}}`, `{{BRANCH_MODEL}}` | The branch model from step 2 |
| `{{STORYBOOK_DIR}}`, `{{STORYBOOK_PORT}}`, `{{STORYBOOK_BRANCH}}` | The Storybook folder, port and branch, or see step 5 |
| `{{CODE_REMOTE}}`, `{{DOCS_REMOTE}}`, `{{STORYBOOK_REMOTE}}` | Each repo's remote, or `none` |
| `{{DOCS_GIT}}` | How the docs folder is tracked in git |
| `{{PUBLISH_EFFECT}}` | What a push to the publishing branch does |
| `{{COMMANDS}}` | How to run, build, test and check the project |
| `{{PLAN_FILE}}`, `{{DECISIONS_FILE}}` | Where the plan and the open decisions list live |
| `{{TOKEN_FILE}}`, `{{COMPONENT_FOLDERS}}`, `{{COMPONENT_LIBRARY}}` | The standards, or `none` |
| `{{SERVICE_REGISTRY}}`, `{{TEST_SUITE}}` | Where each is, or `None.` |
| `{{REVIEW_BAR}}`, `{{BOUNDARIES}}` | What done looks like, and what must never appear |
| `{{TRELLO_BOARD_NAME}}`, `{{TRELLO_BOARD_ID}}` | The board from step 3 |
| `{{BOARD_ID}}` in `board/board.conf` | The same board id. This is the one the hooks read |
| `{{LIST_ID_NEXT}}`, `{{LIST_ID_RESEARCH}}`, `{{LIST_ID_DESIGN}}` | The list IDs from step 3 |
| `{{LIST_ID_NOW}}`, `{{LIST_ID_QA}}`, `{{LIST_ID_DONE}}` | The list IDs from step 3 |
| `{{TOOLS}}` | The optional tools in use, from step 5 |

When no `{{` remains outside this file, tell the user setup is done. Then:

1. Ask them to restart the orchestrator, so it boots with the finished files.
2. Remind them how to start each agent they chose, from step 6.
3. Tell them they can come back to you any time to change any of it, and that they do not need to
   remember what they skipped. Asking is enough.

**If some placeholders are still unfilled, do not call setup done.** List what is left, say what each one
affects, and say which are optional. Then let the user choose. A user who knowingly leaves Storybook unset
is finished; a user who does not know it is unset is not.
