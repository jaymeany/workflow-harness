#!/usr/bin/env bash
#
# Workflow harness installer.
#
# It does four mechanical things and then gets out of the way: checks this
# computer has what the hooks need, asks for a workspace name and a project
# name, downloads the harness into your home folder under those names, and
# starts the orchestrator.
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
step "Two names. Letters, digits, hyphens and underscores."

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

say "The workspace holds every project you run the harness on."
WORKSPACE="$(ask_name "  Workspace name" "workspace")"
say ""
say "The project is the first thing you will build in it."
PROJECT="$(ask_name "  Project name" "project")"

TARGET="$HOME/$WORKSPACE"
[ ! -e "$TARGET" ] || die "$TARGET already exists. Move it, or choose another workspace name, then run this script again."

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

mv "$tmp/unpacked/$WORKSPACE_SRC" "$TARGET"
mv "$TARGET/$PROJECT_SRC" "$TARGET/$PROJECT"
[ -f "$tmp/unpacked/LICENSE" ] && mv "$tmp/unpacked/LICENSE" "$TARGET/LICENSE" || true
find "$TARGET" -name '.DS_Store' -delete 2>/dev/null || true

ORCHESTRATOR="$TARGET/$PROJECT/docs/agent-workflows/orchestrator"
[ -d "$ORCHESTRATOR" ] || { rm -rf "$TARGET"; die "The orchestrator folder is missing. Nothing was kept."; }

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
