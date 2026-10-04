#!/usr/bin/env bash
#
# Workflow harness installer.
#
# It does four mechanical things and then gets out of the way: checks this
# computer has what the hooks need, asks whether the folder it runs from is the
# project, the workspace or neither, shows the folders it will set up and lets
# the user change them, downloads the harness there, and starts the orchestrator.
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
step "Where the harness goes."

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
HOME_DIR="$(cd "$HOME" && pwd -P)"
[ -w "$HERE" ] || die "Cannot write to $HERE. Change to a folder you own, then run this script again."

# The hooks find the project three levels up from an agent's folder, and the
# workspace one level above that. So the project must sit directly inside the
# workspace. Any folders above the workspace are the user's own business.
say "The harness needs this shape. The project sits directly inside the workspace.

  workspace/                 CLAUDE.md: rules for every project in it
  └── project/               CLAUDE.md, your code, docs/
      └── docs/agent-workflows/
          └── orchestrator/  and research, designer, dev, qa

Folders above the workspace can be anything.

You are in $HERE" > /dev/tty

show_here() {
  say "
This folder holds:" > /dev/tty
  if [ -n "$(ls -A "$HERE" 2>/dev/null)" ]; then
    ls -A "$HERE" | head -n 20 | sed 's/^/  /' > /dev/tty
  else
    say "  nothing" > /dev/tty
  fi
  say "
Choose p if this folder is the one project, empty or holding its code.
Choose w if it holds your projects, or will.
Choose n to keep the harness in a new folder of its own, below this one." > /dev/tty
}

# Sets LAYOUT to p, w or n. "Don't know" shows the folder and asks again.
ask_layout() {
  local answer=""
  say "
What is this folder?
  p  the project. The harness goes in here.
  w  the workspace. A new project folder goes inside it.
  n  neither. A new workspace folder goes inside it, with the project inside that.
  d  don't know
  q  stop" > /dev/tty
  while true; do
    printf '  Choose p, w, n or d: ' > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    case "$answer" in
      p|P) LAYOUT=p; return 0 ;;
      w|W) LAYOUT=w; return 0 ;;
      n|N) LAYOUT=n; return 0 ;;
      d|D|"?") show_here ;;
      q|Q) die "Stopped. Nothing was written." ;;
      *) say "  Choose p, w, n or d." > /dev/tty ;;
    esac
  done
}

# Sets WS_DIR, PROJECT_DIR and PROJECT from LAYOUT, asking for names where the
# layout makes a new folder. Returns 1, with the reason shown, if the plan
# cannot work, so the user can choose again.
plan() {
  case "$LAYOUT" in
    p) PROJECT_DIR="$HERE"; WS_DIR="$(dirname "$HERE")"; PROJECT="$(basename "$HERE")" ;;
    w) WS_DIR="$HERE"
       PROJECT="$(ask_name "  Project name" "${PROJECT:-project}")"
       PROJECT_DIR="$WS_DIR/$PROJECT" ;;
    n) WORKSPACE="$(ask_name "  Workspace name" "${WORKSPACE:-workspace}")"
       WS_DIR="$HERE/$WORKSPACE"
       PROJECT="$(ask_name "  Project name" "${PROJECT:-project}")"
       PROJECT_DIR="$WS_DIR/$PROJECT" ;;
  esac

  # A workspace CLAUDE.md in the home folder would load into every Claude
  # session on this computer, so the home folder cannot be the workspace.
  if [ "$WS_DIR" = "$HOME_DIR" ] || [ "$PROJECT_DIR" = "$HOME_DIR" ]; then
    say "
  That makes the home folder the $( [ "$WS_DIR" = "$HOME_DIR" ] && echo workspace || echo project ). Its CLAUDE.md would load
  into every Claude session on this computer. Choose another layout, or make a
  folder for the harness, change to it, and run this script again." > /dev/tty
    return 1
  fi
  if [ "$LAYOUT" = n ] && [ -e "$WS_DIR" ]; then
    say "
  $WS_DIR already exists. Choose another workspace name, or change to it and choose w." > /dev/tty
    return 1
  fi
  if [ "$LAYOUT" != p ] && [ -e "$PROJECT_DIR" ]; then
    say "
  $PROJECT_DIR already exists. Choose another project name, or change to it and choose p." > /dev/tty
    return 1
  fi
  if [ "$LAYOUT" = p ]; then
    for name in CLAUDE.md docs; do
      if [ -e "$PROJECT_DIR/$name" ]; then
        say "
  This folder already has $name, and the harness would write its own.
  Move it aside, or choose another layout." > /dev/tty
        return 1
      fi
    done
    if [ ! -e "$WS_DIR/CLAUDE.md" ] && [ ! -w "$WS_DIR" ]; then
      say "
  Cannot write the workspace CLAUDE.md to $WS_DIR. Choose another layout." > /dev/tty
      return 1
    fi
  fi
  return 0
}

# One line of the tree: indent, folder name, note. printf pads by bytes and
# the box-drawing characters are three bytes each, so pad by hand.
row() {
  local plain="${1//└──/xxx}"
  local pad=$(( 32 - ${#plain} ))
  [ "$pad" -ge 1 ] || pad=1
  printf '  %s%*s%s\n' "$1" "$pad" "" "$2" > /dev/tty
}

draw_plan() {
  local ws_name ws_note proj_note
  ws_name="$(basename "$WS_DIR")/"
  if [ ! -e "$WS_DIR" ]; then
    ws_note="workspace. New folder, with CLAUDE.md."
  elif [ -e "$WS_DIR/CLAUDE.md" ]; then
    ws_note="workspace. Its CLAUDE.md is kept."
  else
    ws_note="workspace. CLAUDE.md is added."
  fi
  if [ "$LAYOUT" = p ]; then
    proj_note="project. You are here. CLAUDE.md and docs/ are added."
  else
    proj_note="project. New folder."
  fi
  [ "$LAYOUT" = w ] && ws_note="$ws_note You are here."

  say "
This is what will be set up.
" > /dev/tty
  if [ "$LAYOUT" = n ]; then
    say "In $(dirname "$HERE")" > /dev/tty
    say "" > /dev/tty
    row "$(basename "$HERE")/" "You are here."
    row "└── $ws_name" "$ws_note"
    row "    └── $PROJECT/" "$proj_note"
    row "        └── docs/agent-workflows/" "The five agents. The orchestrator starts here."
  else
    say "In $(dirname "$WS_DIR")" > /dev/tty
    say "" > /dev/tty
    row "$ws_name" "$ws_note"
    row "└── $PROJECT/" "$proj_note"
    row "    └── docs/agent-workflows/" "The five agents. The orchestrator starts here."
  fi
  say "
Anything already in these folders is left alone." > /dev/tty
}

# Returns 0 to go ahead, 1 to edit. q stops.
confirm_plan() {
  local answer=""
  while true; do
    printf '\n  Set it up like this? y to go ahead, e to change it, q to stop [y/e/q]: ' > /dev/tty
    IFS= read -r answer < /dev/tty || die "No answer. Stopping."
    case "$answer" in
      y|Y|yes|Yes|YES) return 0 ;;
      e|E) return 1 ;;
      q|Q) die "Stopped. Nothing was written." ;;
      *) say "  Answer y, e or q." > /dev/tty ;;
    esac
  done
}

LAYOUT="" WS_DIR="" PROJECT_DIR="" PROJECT="" WORKSPACE=""
while true; do
  ask_layout
  plan || continue
  draw_plan
  confirm_plan && break
done

# ------------------------------------------------------------------ download
step "Downloading the harness."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
curl -fsSL "$url" -o "$tmp/harness.tar.gz" || die "Download failed from $url"

# Unpack whole, then move what is wanted. Matching member names by pattern
# behaves differently under GNU tar and bsdtar; moving a folder does not.
mkdir -p "$tmp/unpacked"
tar -xzf "$tmp/harness.tar.gz" -C "$tmp/unpacked" --strip-components=1 \
  || die "Could not unpack the harness."

src="$tmp/unpacked/$WORKSPACE_SRC/$PROJECT_SRC"
[ -f "$tmp/unpacked/$WORKSPACE_SRC/CLAUDE.md" ] && [ -d "$src/docs/agent-workflows/orchestrator" ] \
  || die "The download did not contain what was expected. Nothing was written."
find "$src" -name '.DS_Store' -delete 2>/dev/null || true

# The project folder may already exist and hold the user's own files. Check
# every name first, so a clash stops before anything is written.
for entry in "$src"/* "$src"/.[!.]*; do
  [ -e "$entry" ] || continue
  [ ! -e "$PROJECT_DIR/$(basename "$entry")" ] \
    || die "$PROJECT_DIR/$(basename "$entry") already exists. Nothing was written."
done

mkdir -p "$PROJECT_DIR"
for entry in "$src"/* "$src"/.[!.]*; do
  [ -e "$entry" ] || continue
  mv "$entry" "$PROJECT_DIR/"
done

# The workspace may already hold a CLAUDE.md, from an earlier project or the
# user's own. An existing one is kept. The LICENSE travels with a new one.
if [ -e "$WS_DIR/CLAUDE.md" ]; then
  say "  kept          $WS_DIR/CLAUDE.md, which was already there"
else
  mv "$tmp/unpacked/$WORKSPACE_SRC/CLAUDE.md" "$WS_DIR/CLAUDE.md"
  if [ ! -e "$WS_DIR/LICENSE" ] && [ -f "$tmp/unpacked/LICENSE" ]; then
    mv "$tmp/unpacked/LICENSE" "$WS_DIR/LICENSE"
  fi
fi

ORCHESTRATOR="$PROJECT_DIR/docs/agent-workflows/orchestrator"
say "  workspace     $WS_DIR"
say "  project       $PROJECT_DIR"
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
