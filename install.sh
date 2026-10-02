#!/usr/bin/env bash
#
# Workflow harness installer.
#
# It does four mechanical things and then gets out of the way: checks this
# computer has what the hooks need, asks whether the folder it runs from is the
# workspace (and for a workspace name if not) and for a project name, downloads
# the harness there under those names, and starts the orchestrator.
#
# Renaming the two template folders is the one setup task that has to happen
# while Claude Code is closed, because the agent sessions live inside them.
# This script is that moment. It renames the folders on disk and nothing else:
# every {{placeholder}} is left unfilled, so the orchestrator still runs
# FIRST_START.md from step 1 and still records the names in the CLAUDE.md files.
#
# It never asks for or writes a key, a token or a password. Trello, git, the
# MCP server, the code folder and the project'"'"'s stack are all settled in the
# conversation with the orchestrator, after this script hands off.
#
# Run it from a file, not from a pipe:
#
#   curl -fsSL https://raw.githubusercontent.com/jaymeany/workflow-harness/main/install.sh -o harness-install.sh
#   bash harness-install.sh
#
set -euo pipefail

REPO="jaymeany/workflow-harness"
BRANCH="main"
WORKSPACE_SRC="Primary-project-name"
PROJECT_SRC="app-or-project-name"
MIN_CLAUDE="2.1.224"

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
die()  { printf '\n%s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- pipe guard
# A piped script shares stdin with the pipe, so the questions below would read
# the script's own text and Claude Code would have no terminal to start in.
if [ ! -t 0 ]; then
  die "Run this from a file, not a pipe:

  curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/install.sh -o harness-install.sh
  bash harness-install.sh"
fi

say "Workflow harness installer"

# ----------------------------------------------------------------- preflight
step "Checking this computer."

os="$(uname -s)"
case "$os" in
  Darwin) say "  system        Mac" ;;
  Linux)  say "  system        Linux" ;;
  *)      die "This is $os. The hooks are bash scripts and need a bash shell.
On Windows, install WSL and run this script inside it, where everything works as on Linux." ;;
esac

missing=""
for tool in git curl jq pgrep; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] || die "Missing:$missing

The hooks need these. A hook that cannot find its tool allows everything without
checking, so install them before going on.
  Mac:   brew install${missing}
  Linux: use your package manager"
say "  tools         git, curl, jq, pgrep"

command -v claude >/dev/null 2>&1 || die "Claude Code is not installed, or is not on PATH.
Install it, open a new terminal, and run this script again."

claude_version="$(claude --version 2>/dev/null | awk '{print $1}')"
[ -n "$claude_version" ] || die "Could not read the Claude Code version from 'claude --version'."
oldest="$(printf '%s\n%s\n' "$MIN_CLAUDE" "$claude_version" | sort -V | head -n1)"
if [ "$oldest" != "$MIN_CLAUDE" ] && [ "$claude_version" != "$MIN_CLAUDE" ]; then
  die "Claude Code $claude_version is older than $MIN_CLAUDE.
The agents reach each other with ListAgents and SendMessage, which need $MIN_CLAUDE or later.
Run 'claude update', then run this script again."
fi
say "  Claude Code   $claude_version"

# --------------------------------------------------------------------- names
# Renaming these folders is the one setup task that has to happen while Claude
# Code is closed, because the orchestrator's session lives inside them.
step "Where the workspace goes."

ask_name() {
  local prompt="$1" default="$2" answer=""
  while true; do
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    [ -n "$answer" ] || answer="$default"
    if printf '%s' "$answer" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]*$'; then
      printf '%s' "$answer"
      return 0
    fi
    say "  Use letters, digits, hyphens and underscores. No spaces or slashes." > /dev/tty
  done
}

HERE="$(pwd -P)"
[ -w "$HERE" ] || die "Cannot write to $HERE. Change to a folder you own, then run this script again."

explain_workspace() {
  say "
A workspace is the folder that holds your projects. Its CLAUDE.md holds the
rules every agent in every project there follows. Each project is a folder
inside it, with its own code, docs and agents.

Answer y if this folder is that folder: an empty folder you made for it, or one
where you already ran this installer for another project. Answer n to make a
new workspace folder inside this one.

This folder holds:" > /dev/tty
  if [ -n "$(ls -A "$HERE" 2>/dev/null)" ]; then
    ls -A "$HERE" | head -n 20 | sed 's/^/  /' > /dev/tty
  else
    say "  nothing" > /dev/tty
  fi
  say "" > /dev/tty
}

# Returns 0 for yes, 1 for no. "Don't know" explains and asks again.
ask_workspace() {
  local answer=""
  while true; do
    printf '  Is this folder the workspace? yes, no, or don'"'"'t know [y/n/d]: ' > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    case "$answer" in
      y|Y|yes|Yes|YES) return 0 ;;
      n|N|no|No|NO)    return 1 ;;
      d|D|"don't know"|"Don't know"|"dont know"|"?") explain_workspace ;;
      *) say "  Answer y, n or d." > /dev/tty ;;
    esac
  done
}

say "The workspace holds every project you run the harness on."
say "You are in $HERE"
if ask_workspace; then
  # A workspace CLAUDE.md in the home folder would load into every Claude
  # session on this computer, so the home folder cannot be the workspace.
  [ "$HERE" != "$(cd "$HOME" && pwd -P)" ] || die "The home folder cannot be the workspace. Its CLAUDE.md would load into every Claude session on this computer.
Make a folder for the workspace, change to it, and run this script again."
  TARGET="$HERE"
else
  say "Names use letters, digits, hyphens and underscores."
  WORKSPACE="$(ask_name "  Workspace name" "workspace")"
  TARGET="$HERE/$WORKSPACE"
  [ ! -e "$TARGET" ] || die "$TARGET already exists. Change to it and answer y, or choose another workspace name, then run this script again."
fi

say ""
say "The project is the first thing you will build in it."
PROJECT="$(ask_name "  Project name" "project")"
[ ! -e "$TARGET/$PROJECT" ] || die "$TARGET/$PROJECT already exists. Move it, or choose another project name, then run this script again."

# ------------------------------------------------------------------ download
step "Downloading the harness into $TARGET"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
curl -fsSL "$url" -o "$tmp/harness.tar.gz" || die "Download failed from $url"

# Unpack whole, then move what is wanted. Matching member names by pattern
# behaves differently under GNU tar and bsdtar; moving a folder does not.
mkdir -p "$tmp/unpacked"
tar -xzf "$tmp/harness.tar.gz" -C "$tmp/unpacked" --strip-components=1 \
  || die "Could not unpack the harness."

[ -f "$tmp/unpacked/$WORKSPACE_SRC/CLAUDE.md" ] && [ -d "$tmp/unpacked/$WORKSPACE_SRC/$PROJECT_SRC" ] \
  || die "The download did not contain what was expected. Nothing was written."

# The workspace folder may already exist, and may already hold a workspace
# CLAUDE.md from an earlier project. An existing CLAUDE.md or LICENSE is kept.
mkdir -p "$TARGET"
mv "$tmp/unpacked/$WORKSPACE_SRC/$PROJECT_SRC" "$TARGET/$PROJECT"
find "$TARGET/$PROJECT" -name '.DS_Store' -delete 2>/dev/null || true

ORCHESTRATOR="$TARGET/$PROJECT/docs/agent-workflows/orchestrator"
[ -d "$ORCHESTRATOR" ] || { rm -rf "$TARGET/$PROJECT"; die "The orchestrator folder is missing. Nothing was kept."; }

if [ -e "$TARGET/CLAUDE.md" ]; then
  say "  kept          $TARGET/CLAUDE.md, which was already there"
else
  mv "$tmp/unpacked/$WORKSPACE_SRC/CLAUDE.md" "$TARGET/CLAUDE.md"
fi
if [ ! -e "$TARGET/LICENSE" ] && [ -f "$tmp/unpacked/LICENSE" ]; then
  mv "$tmp/unpacked/LICENSE" "$TARGET/LICENSE"
fi

say "  workspace     $TARGET"
say "  project       $TARGET/$PROJECT"
say "  orchestrator  $ORCHESTRATOR"

# -------------------------------------------------------------------- hand off
step "Starting the orchestrator. It takes it from here.

It will speak first. It will ask what you want to build, then walk you through
git, Trello, the folder and stack questions, and the other agents. Keys and
tokens go in your shell profile, typed by you, never in the chat.

You can stop at any point. To come back, open a terminal and run:

  cd $ORCHESTRATOR && claude

Press Return to start."
IFS= read -r _ < /dev/tty || true

# exec replaces this process, so the EXIT trap will not fire.
rm -rf "$tmp"
trap - EXIT

# Launch with no prompt. The orchestrator's SessionStart hook,
# load-first-start-check.sh, sees the unfilled placeholders and tells the
# session to lead with FIRST_START.md whatever the user opens with. A prompt
# here would only compete with it.
cd "$ORCHESTRATOR"
exec claude
